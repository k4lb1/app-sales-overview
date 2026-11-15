import Foundation

/// Which App Store: Apple keeps separate charts and searches for iPhone, iPad and Mac apps. Vision Pro apps have
/// neither in the public feeds.
public enum StorePlatform: String, Codable, CaseIterable, Sendable {
    case iPhone, iPad, mac

    var feed: String {
        switch self {
        case .iPhone: "applications"
        case .iPad: "ipadapplications"
        case .mac: "macapps"
        }
    }

    var searchEntity: String {
        switch self {
        case .iPhone: "software"
        case .iPad: "iPadSoftware"
        case .mac: "macSoftware"
        }
    }
}

/// One of the App Store's top charts: free, paid or grossing, for iPhone, iPad or Mac apps, in one country, over all
/// categories or one. Apple's public feeds give the first 100 places.
public struct TopChart: Codable, Hashable, Sendable {
    public enum List: String, Codable, CaseIterable, Sendable {
        case free, paid, grossing
    }

    public var list: List
    public var platform: StorePlatform
    /// ISO code in lower case, e.g. "de".
    public var country: String
    /// Apple's category ID, e.g. 6011 for Music; nil for all categories.
    public var genre: Int?

    public init(list: List, platform: StorePlatform, country: String, genre: Int?) {
        self.list = list
        self.platform = platform
        self.country = country.lowercased()
        self.genre = genre
    }

    var url: URL {
        let feed = "top\(list.rawValue)\(platform.feed)"
        let genrePart = genre.map { "/genre=\($0)" } ?? ""
        return URL(string: "https://itunes.apple.com/\(country)/rss/\(feed)/limit=100\(genrePart)/json")!
    }

    /// The app IDs in the chart, first place first.
    public func load() async throws -> [String] {
        struct Feed: Decodable {
            struct Body: Decodable {
                struct Entry: Decodable {
                    struct ID: Decodable {
                        struct Attributes: Decodable { let id: String; enum CodingKeys: String, CodingKey { case id = "im:id" } }
                        let attributes: Attributes
                    }
                    let id: ID
                }
                let entry: [Entry]?
            }
            let feed: Body
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return (try JSONDecoder().decode(Feed.self, from: data).feed.entry ?? []).map(\.id.attributes.id)
    }
}

/// What the public App Store says about an app: its category, price, rating and version. Works for any app, so
/// also for competitors.
public struct StoreListing: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var mac: Bool
    /// Whether it runs on the iPad too, so it's in the iPad charts.
    public var iPad: Bool
    public var genre: Int
    public var genreName: String
    public var price: Double
    public var currency: String
    public var rating: Double
    public var ratings: Int
    public var version: String
    public var released: Date?
    public var icon: URL?
    public var developer: String

    public init(id: String, name: String, mac: Bool, iPad: Bool = false, genre: Int, genreName: String, price: Double, currency: String,
                rating: Double, ratings: Int, version: String, released: Date?, icon: URL?, developer: String = "") {
        self.id = id
        self.name = name
        self.mac = mac
        self.iPad = iPad
        self.genre = genre
        self.genreName = genreName
        self.price = price
        self.currency = currency
        self.rating = rating
        self.ratings = ratings
        self.version = version
        self.released = released
        self.icon = icon
        self.developer = developer
    }

    /// The listings in one country's store; apps not sold there are missing.
    public static func load(ids: [String], country: String) async throws -> [StoreListing] {
        guard !ids.isEmpty else { return [] }
        return try await request("lookup", [URLQueryItem(name: "id", value: ids.joined(separator: ",")),
                                            URLQueryItem(name: "country", value: country.lowercased())])
    }

    /// Apps whose name or developer matches, as the App Store's search finds them; or the one app an App Store link
    /// ("…/id123456789") points to.
    public static func search(_ text: String, country: String, platform: StorePlatform = .iPhone) async throws -> [StoreListing] {
        if let match = text.firstMatch(of: /id(\d{6,})/) { return try await load(ids: [String(match.1)], country: country) }
        return try await request("search", [URLQueryItem(name: "term", value: text), URLQueryItem(name: "country", value: country.lowercased()),
                                            URLQueryItem(name: "entity", value: platform.searchEntity),
                                            URLQueryItem(name: "limit", value: "15")])
    }

    /// Where an app comes in the App Store's search for `term`: 1 for the first result, nil when it isn't among the
    /// first 200. Apple's public search is close to what the App Store app shows, which also weighs the person searching.
    public static func searchPlace(of appID: String, for term: String, country: String, platform: StorePlatform) async throws -> Int? {
        let results = try await request("search", [URLQueryItem(name: "term", value: term), URLQueryItem(name: "country", value: country.lowercased()),
                                                   URLQueryItem(name: "entity", value: platform.searchEntity),
                                                   URLQueryItem(name: "limit", value: "200")])
        return results.firstIndex { $0.id == appID }.map { $0 + 1 }
    }

    private static func request(_ path: String, _ query: [URLQueryItem]) async throws -> [StoreListing] {
        struct Answer: Decodable {
            struct App: Decodable {
                let trackId: Int
                let trackName: String
                let kind: String?
                let primaryGenreId: Int?
                let primaryGenreName: String?
                let price: Double?
                let currency: String?
                let averageUserRating: Double?
                let userRatingCount: Int?
                let version: String?
                let currentVersionReleaseDate: String?
                let artworkUrl100: String?
                let artistName: String?
                let supportedDevices: [String]?
            }
            let results: [App]
        }
        var components = URLComponents(string: "https://itunes.apple.com/\(path)")!
        components.queryItems = query
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw StoreError.status(status) }
        return try JSONDecoder().decode(Answer.self, from: data).results.map { app in
            StoreListing(id: String(app.trackId), name: app.trackName, mac: app.kind == "mac-software",
                         iPad: app.supportedDevices?.contains { $0.hasPrefix("iPad") } ?? false, genre: app.primaryGenreId ?? 0,
                         genreName: app.primaryGenreName ?? "", price: app.price ?? 0, currency: app.currency ?? "",
                         rating: app.averageUserRating ?? 0, ratings: app.userRatingCount ?? 0, version: app.version ?? "",
                         released: app.currentVersionReleaseDate.flatMap { ISO8601DateFormatter().date(from: $0) },
                         icon: app.artworkUrl100.flatMap(URL.init(string:)), developer: app.artistName ?? "")
        }
    }
}

public enum StoreError: Error, LocalizedError {
    /// 403 or 429: Apple's public search allows about 20 requests a minute.
    case status(Int)

    public var errorDescription: String? {
        switch self {
        case .status(let code) where code == 403 || code == 429: "The App Store asked to slow down (HTTP \(code)); it tries again later."
        case .status(let code): "The App Store answered HTTP \(code)."
        }
    }
}
