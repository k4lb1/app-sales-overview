import Foundation

public struct StoreApp: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var bundleID: String
    public var sku: String
    /// Newest first.
    public var versions: [Version]

    public struct Version: Codable, Hashable, Sendable {
        public var string: String
        public var state: String
    }

    public var live: Version? { versions.first { $0.state == "READY_FOR_DISTRIBUTION" } }
    /// A newer version that isn't in the store yet (being prepared, waiting, in review, rejected …).
    public var pending: Version? { versions.first.flatMap { $0.state == "READY_FOR_DISTRIBUTION" ? nil : $0 } }
}

extension Client {
    public func apps() async throws -> [StoreApp] {
        let data = try await get("/v1/apps", query: ["limit": "200", "fields[apps]": "name,bundleId,sku"])
        let list = try JSONDecoder().decode(Page<AppResource>.self, from: data).data
        return try await withThrowingTaskGroup(of: StoreApp.self) { group in
            for app in list {
                group.addTask {
                    let versions = try await self.get("/v1/apps/\(app.id)/appStoreVersions", query: [
                        "limit": "3", "fields[appStoreVersions]": "versionString,appVersionState",
                    ])
                    let decoded = try JSONDecoder().decode(Page<VersionResource>.self, from: versions).data
                    return StoreApp(id: app.id, name: app.attributes.name, bundleID: app.attributes.bundleId,
                                    sku: app.attributes.sku ?? "",
                                    versions: decoded.map { .init(string: $0.attributes.versionString, state: $0.attributes.appVersionState ?? "") })
                }
            }
            var result: [StoreApp] = []
            for try await app in group { result.append(app) }
            return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// The store icon, from Apple's public lookup. An app is found only in a storefront that sells it, so this asks
    /// the given ones in turn (the device's own first). Nil for apps that aren't in the store yet.
    public static func iconURL(appID: String, storefronts: [String]) async -> URL? {
        for storefront in storefronts {
            guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(appID)&country=\(storefront)"),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let lookup = try? JSONDecoder().decode(Lookup.self, from: data),
                  let artwork = lookup.results.first?.artworkUrl512 ?? lookup.results.first?.artworkUrl100 else { continue }
            return URL(string: artwork)
        }
        return nil
    }
}

private struct Page<Item: Decodable>: Decodable { var data: [Item] }

private struct AppResource: Decodable {
    var id: String
    var attributes: Attributes
    struct Attributes: Decodable { var name: String; var bundleId: String; var sku: String? }
}

private struct VersionResource: Decodable {
    var attributes: Attributes
    struct Attributes: Decodable { var versionString: String; var appVersionState: String? }
}

private struct Lookup: Decodable {
    var results: [Result]
    struct Result: Decodable { var artworkUrl512: String?; var artworkUrl100: String? }
}
