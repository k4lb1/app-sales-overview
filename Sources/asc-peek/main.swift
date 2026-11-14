import ASCKit
import Foundation

// Prints what App Store Connect returns for a key in ~/.appstoreconnect (config.json + AuthKey_<keyID>.p8).
// Usage: swift run asc-peek                     apps, versions, reviews
//        swift run asc-peek raw <path> k=v …    e.g. raw /v1/apps limit=5
//        swift run asc-peek post <path> <file>  posts the JSON in <file>, e.g. to create a localization
//        swift run asc-peek sales [yyyy-MM-dd]  the daily sales summary (default: yesterday)
//        swift run asc-peek request-analytics   asks Apple to produce ongoing analytics reports for every app
//        swift run asc-peek discovery           the store analytics instances per app, and the first lines
//        swift run asc-peek report <path> k=v …  any gzipped report, e.g. report /v1/financeReports filter[reportType]=FINANCIAL …

let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".appstoreconnect")
let config = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "config.json"))) as! [String: String]
let keyID = config["keyID"]!
let pem = try String(contentsOf: folder.appending(path: "AuthKey_\(keyID).p8"), encoding: .utf8)
let client = try Client(key: APIKey(issuer: config["issuer"]!, keyID: keyID, privateKeyPEM: pem))

func json(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

let arguments = CommandLine.arguments.dropFirst()

func query(_ pairs: ArraySlice<String>) -> [String: String] {
    var query: [String: String] = [:]
    for pair in pairs {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2 { query[parts[0]] = parts[1] }
    }
    return query
}

if arguments.first == "raw", let path = arguments.dropFirst().first {
    let data = try await client.get(path, query: query(arguments.dropFirst(2)))
    let pretty = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: pretty, as: UTF8.self))
    exit(0)
}

if arguments.first == "post", let path = arguments.dropFirst().first, let file = arguments.dropFirst(2).first {
    let body = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: file))) as! [String: Any]
    print(String(decoding: try await client.post(path, json: body), as: UTF8.self))
    exit(0)
}

if arguments.first == "sales" {
    let day = arguments.dropFirst().first ?? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return formatter.string(from: Date().addingTimeInterval(-86_400))
    }()
    let data = try await client.get("/v1/salesReports", query: [
        "filter[frequency]": "DAILY", "filter[reportType]": "SALES", "filter[reportSubType]": "SUMMARY",
        "filter[vendorNumber]": config["vendorNumber"]!, "filter[reportDate]": day, "filter[version]": "1_1",
    ])
    print(String(decoding: try Gzip.unzip(data), as: UTF8.self))
    exit(0)
}

if arguments.first == "report", let path = arguments.dropFirst().first {
    var query = query(arguments.dropFirst(2))
    query["filter[vendorNumber]"] = config["vendorNumber"]!
    print(String(decoding: try Gzip.unzip(try await client.get(path, query: query)), as: UTF8.self))
    exit(0)
}

let apps = json(try await client.get("/v1/apps", query: ["limit": "200", "fields[apps]": "name,bundleId"]))["data"] as? [[String: Any]] ?? []
if arguments.first == "request-analytics" {
    for app in apps {
        let id = app["id"] as! String
        let name = (app["attributes"] as? [String: Any])?["name"] as? String ?? id
        let existing = json(try await client.get("/v1/apps/\(id)/analyticsReportRequests"))["data"] as? [[String: Any]] ?? []
        let kinds = existing.compactMap { ($0["attributes"] as? [String: Any])?["accessType"] as? String }
        if kinds.contains("ONGOING") {
            print("\(name): schon angefordert")
            continue
        }
        _ = try await client.post("/v1/analyticsReportRequests", json: ["data": [
            "type": "analyticsReportRequests",
            "attributes": ["accessType": "ONGOING"],
            "relationships": ["app": ["data": ["type": "apps", "id": id]]],
        ]])
        print("\(name): angefordert")
    }
    exit(0)
}

if arguments.first == "discovery" {
    for app in apps {
        let id = app["id"] as! String
        let request = try await client.ensureAnalyticsRequest(appID: id)
        let instances = try await client.reportInstances(requestID: request, name: Client.discoveryReport)
        print("\((app["attributes"] as? [String: Any])?["name"] ?? id): \(instances.count) Tage")
        if let newest = instances.first {
            for row in try await client.discoveryRows(instanceID: newest.id).prefix(5) { print("   \(row)") }
        }
    }
    exit(0)
}

print("\(apps.count) Apps\n")
for app in apps {
    let id = app["id"] as! String
    let attributes = app["attributes"] as? [String: Any] ?? [:]
    let name = attributes["name"] as? String ?? "?"
    let versions = json(try await client.get("/v1/apps/\(id)/appStoreVersions",
                                             query: ["limit": "2", "fields[appStoreVersions]": "versionString,appVersionState,createdDate"]))["data"] as? [[String: Any]] ?? []
    let states = versions.map { version in
        let a = version["attributes"] as? [String: Any] ?? [:]
        return "\(a["versionString"] as? String ?? "?") \(a["appVersionState"] as? String ?? "?")"
    }
    print("\(name) (\(attributes["bundleId"] as? String ?? "")) · id \(id)")
    print("   Versionen: \(states.joined(separator: " · "))")

    let reviews = json(try await client.get("/v1/apps/\(id)/customerReviews",
                                            query: ["limit": "3", "sort": "-createdDate"]))["data"] as? [[String: Any]] ?? []
    for review in reviews {
        let a = review["attributes"] as? [String: Any] ?? [:]
        let stars = String(repeating: "★", count: a["rating"] as? Int ?? 0)
        print("   \(stars) \(a["title"] as? String ?? "") (\(a["territory"] as? String ?? ""), \((a["createdDate"] as? String ?? "").prefix(10)))")
    }
    if reviews.isEmpty { print("   keine Bewertungen") }
}
