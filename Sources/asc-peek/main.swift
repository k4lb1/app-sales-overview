import ASCKit
import Foundation

// Prints what App Store Connect returns for a key in ~/.appstoreconnect (config.json + AuthKey_<keyID>.p8).
let usage = """
    Usage: swift run asc-peek                     apps, versions, reviews
           swift run asc-peek raw <path> k=v …    e.g. raw /v1/apps limit=5
           swift run asc-peek post <path> <file>  posts the JSON in <file>, e.g. to create a localization
           swift run asc-peek patch <path> <file> sends the JSON in <file> as a change, e.g. to store texts
           swift run asc-peek delete <path>       removes a resource, e.g. a screenshot
           swift run asc-peek sales [yyyy-MM-dd]  the daily sales summary (default: yesterday)
           swift run asc-peek request-analytics   asks Apple to produce ongoing analytics reports for every app
           swift run asc-peek discovery           the store analytics instances per app, and the first lines
           swift run asc-peek report <path> k=v … any gzipped report, e.g. report /v1/financeReports filter[reportType]=FINANCIAL …
    """

struct Failure: Error, CustomStringConvertible {
    let description: String
}

let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".appstoreconnect")

func setting(_ name: String, in config: [String: String]) throws -> String {
    guard let value = config[name] else { throw Failure(description: "\(name) is missing in ~/.appstoreconnect/config.json") }
    return value
}

func query(_ pairs: ArraySlice<String>) -> [String: String] {
    var query: [String: String] = [:]
    for pair in pairs {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2 { query[parts[0]] = parts[1] }
    }
    return query
}

func json(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

func yesterdayInCupertino() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
    return formatter.string(from: Date().addingTimeInterval(-86_400))
}

func run(_ arguments: ArraySlice<String>) async throws {
    let config = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "config.json"))) as? [String: String] ?? [:]
    let keyID = try setting("keyID", in: config)
    let pem = try String(contentsOf: folder.appending(path: "AuthKey_\(keyID).p8"), encoding: .utf8)
    let client = try Client(key: APIKey(issuer: try setting("issuer", in: config), keyID: keyID, privateKeyPEM: pem))
    let rest = Array(arguments.dropFirst())

    switch (arguments.first, rest.count) {
    case (nil, _):
        try await overview(client)

    case ("raw", 1...):
        let data = try await client.get(rest[0], query: query(arguments.dropFirst(2)))
        let pretty = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: pretty, as: UTF8.self))

    case ("post", 2), ("patch", 2):
        guard let body = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: rest[1]))) as? [String: Any] else {
            throw Failure(description: "\(rest[1]) must contain a JSON object")
        }
        let data = arguments.first == "post" ? try await client.post(rest[0], json: body) : try await client.patch(rest[0], json: body)
        print(String(decoding: data, as: UTF8.self))

    case ("delete", 1):
        _ = try await client.delete(rest[0])

    case ("sales", 0...1):
        let data = try await client.get("/v1/salesReports", query: [
            "filter[frequency]": "DAILY", "filter[reportType]": "SALES", "filter[reportSubType]": "SUMMARY",
            "filter[vendorNumber]": try setting("vendorNumber", in: config),
            "filter[reportDate]": rest.first ?? yesterdayInCupertino(), "filter[version]": "1_1",
        ])
        print(String(decoding: try Gzip.unzip(data), as: UTF8.self))

    case ("report", 1...):
        var query = query(arguments.dropFirst(2))
        query["filter[vendorNumber]"] = try setting("vendorNumber", in: config)
        print(String(decoding: try Gzip.unzip(try await client.get(rest[0], query: query)), as: UTF8.self))

    case ("request-analytics", 0):
        for app in try await client.apps() {
            let existing = json(try await client.get("/v1/apps/\(app.id)/analyticsReportRequests"))["data"] as? [[String: Any]] ?? []
            let kinds = existing.compactMap { ($0["attributes"] as? [String: Any])?["accessType"] as? String }
            if kinds.contains("ONGOING") {
                print("\(app.name): already requested")
                continue
            }
            _ = try await client.post("/v1/analyticsReportRequests", json: ["data": [
                "type": "analyticsReportRequests",
                "attributes": ["accessType": "ONGOING"],
                "relationships": ["app": ["data": ["type": "apps", "id": app.id]]],
            ]])
            print("\(app.name): requested")
        }

    case ("discovery", 0):
        for app in try await client.apps() {
            let request = try await client.ensureAnalyticsRequest(appID: app.id)
            let instances = try await client.reportInstances(requestID: request, name: Client.discoveryReport)
            print("\(app.name): \(instances.count) days")
            if let newest = instances.first {
                for row in try await client.discoveryRows(instanceID: newest.id).prefix(5) { print("   \(row)") }
            }
        }

    default:
        throw Failure(description: usage)
    }
}

func overview(_ client: Client) async throws {
    let apps = try await client.apps()
    let reviews = try await withThrowingTaskGroup(of: (String, [Review]).self) { group in
        for app in apps { group.addTask { (app.id, try await client.reviews(appID: app.id, limit: 3)) } }
        return try await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }

    print("\(apps.count) apps\n")
    for app in apps {
        print("\(app.name) (\(app.bundleID)) · id \(app.id)")
        print("   Versions: \(app.versions.prefix(2).map { "\($0.string) \($0.state)" }.joined(separator: " · "))")
        let latest = reviews[app.id] ?? []
        for review in latest {
            let stars = String(repeating: "★", count: review.rating)
            print("   \(stars) \(review.title) (\(review.territory), \(review.date.formatted(.iso8601.year().month().day())))")
        }
        if latest.isEmpty { print("   no reviews") }
    }
}

do {
    try await run(CommandLine.arguments.dropFirst())
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
