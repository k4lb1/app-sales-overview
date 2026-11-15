import Foundation

/// An app in the Play Console, as the Reporting API lists it.
public struct PlayApp: Codable, Hashable, Identifiable, Sendable {
    /// The package name, e.g. "com.example.app"; Google's ID for the app everywhere.
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A review with text; Google's API leaves out ratings without one.
public struct PlayReview: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var package: String
    public var rating: Int
    public var text: String
    public var author: String
    public var date: Date
    /// The developer's public answer and when it was written, if there is one.
    public var reply: String?
    public var replyDate: Date?

    public init(id: String, package: String, rating: Int, text: String, author: String, date: Date, reply: String? = nil, replyDate: Date? = nil) {
        self.id = id
        self.package = package
        self.rating = rating
        self.text = text
        self.author = author
        self.date = date
        self.reply = reply
        self.replyDate = replyDate
    }
}

/// The share of daily users who saw a crash, from Android Vitals.
public struct PlayCrashDay: Codable, Hashable, Sendable {
    /// "yyyy-MM-dd", Pacific time like the reports.
    public var day: String
    public var crashRate: Double
    public var userPerceived: Double
}

/// Talks to Google with the service account: the app list and the crash rates (Play Developer Reporting API),
/// the reviews (Play Developer API) and the report files in the account's Cloud Storage bucket.
public struct PlayClient: Sendable {
    static let scopes = [
        "https://www.googleapis.com/auth/devstorage.read_only",
        "https://www.googleapis.com/auth/androidpublisher",
        "https://www.googleapis.com/auth/playdeveloperreporting",
    ]
    private let tokens: TokenSource

    public init(account: ServiceAccount) throws {
        tokens = try TokenSource(account: account, scopes: Self.scopes)
    }

    /// Every app the service account may see.
    public func apps() async throws -> [PlayApp] {
        struct Page: Decodable {
            struct App: Decodable { let packageName: String; let displayName: String? }
            let apps: [App]?
            let nextPageToken: String?
        }
        var apps: [PlayApp] = [], token: String?
        repeat {
            var components = URLComponents(string: "https://playdeveloperreporting.googleapis.com/v1beta1/apps:search")!
            components.queryItems = [URLQueryItem(name: "pageSize", value: "100")] + (token.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            let page = try JSONDecoder().decode(Page.self, from: try await send(components.url!))
            apps += (page.apps ?? []).map { PlayApp(id: $0.packageName, name: $0.displayName ?? $0.packageName) }
            token = page.nextPageToken
        } while token != nil
        return apps
    }

    /// The names of the files in the bucket under `prefix`, e.g. "stats/installs/".
    public func files(bucket: String, prefix: String) async throws -> [String] {
        struct Page: Decodable {
            struct Item: Decodable { let name: String }
            let items: [Item]?
            let nextPageToken: String?
        }
        var names: [String] = [], token: String?
        repeat {
            var components = URLComponents(string: "https://storage.googleapis.com/storage/v1/b/\(bucket)/o")!
            components.queryItems = [URLQueryItem(name: "prefix", value: prefix)] + (token.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            let page = try JSONDecoder().decode(Page.self, from: try await send(components.url!))
            names += (page.items ?? []).map(\.name)
            token = page.nextPageToken
        } while token != nil
        return names
    }

    public func file(bucket: String, name: String) async throws -> Data {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? name
        return try await send(URL(string: "https://storage.googleapis.com/storage/v1/b/\(bucket)/o/\(encoded)?alt=media")!)
    }

    /// The reviews with text that Google still hands out (the recent ones).
    public func reviews(package: String) async throws -> [PlayReview] {
        struct Page: Decodable {
            struct Review: Decodable {
                struct Comment: Decodable {
                    struct User: Decodable {
                        struct Stamp: Decodable { let seconds: String }
                        let text: String?
                        let starRating: Int?
                        let lastModified: Stamp?
                    }
                    struct Developer: Decodable {
                        let text: String?
                        let lastModified: User.Stamp?
                    }
                    let userComment: User?
                    let developerComment: Developer?
                }
                let reviewId: String
                let authorName: String?
                let comments: [Comment]?
            }
            let reviews: [Review]?
        }
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(package)/reviews?maxResults=100")!
        let page = try JSONDecoder().decode(Page.self, from: try await send(url))
        return (page.reviews ?? []).compactMap { review in
            guard let comment = review.comments?.first(where: { $0.userComment != nil })?.userComment else { return nil }
            let developer = review.comments?.first(where: { $0.developerComment != nil })?.developerComment
            return PlayReview(id: review.reviewId, package: package, rating: comment.starRating ?? 0,
                              text: (comment.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines), author: review.authorName ?? "",
                              date: Date(timeIntervalSince1970: Double(comment.lastModified?.seconds ?? "0") ?? 0),
                              reply: developer?.text, replyDate: developer?.lastModified.map { Date(timeIntervalSince1970: Double($0.seconds) ?? 0) })
        }
    }

    /// Google's limit for an answer.
    public static let replyLimit = 350

    /// Answers a review publicly, or replaces the answer that's there. Google has no way to remove one.
    public func reply(package: String, reviewID: String, text: String) async throws {
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(package)/reviews/\(reviewID):reply")!
        _ = try await send(url, json: ["replyText": text])
    }

    /// The crash rate per day over the last `days`, as far as Google has computed it (usually up to two days ago).
    public func crashRates(package: String, days: Int, now: Date = .now) async throws -> [PlayCrashDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func date(_ offset: Int) -> [String: Any] {
            let day = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: -offset, to: now)!)
            return ["year": day.year!, "month": day.month!, "day": day.day!, "timeZone": ["id": "America/Los_Angeles"]]
        }
        let body: [String: Any] = [
            "timelineSpec": ["aggregationPeriod": "DAILY", "startTime": date(days + 2), "endTime": date(2)],
            "metrics": ["crashRate", "userPerceivedCrashRate"],
        ]
        struct Answer: Decodable {
            struct Row: Decodable {
                struct Time: Decodable { let year: Int; let month: Int; let day: Int }
                struct Metric: Decodable {
                    struct Value: Decodable { let value: String }
                    let metric: String
                    let decimalValue: Value?
                }
                let startTime: Time
                let metrics: [Metric]
            }
            let rows: [Row]?
        }
        let url = URL(string: "https://playdeveloperreporting.googleapis.com/v1beta1/apps/\(package)/crashRateMetricSet:query")!
        let answer = try JSONDecoder().decode(Answer.self, from: try await send(url, json: body))
        return (answer.rows ?? []).map { row in
            func value(_ name: String) -> Double { Double(row.metrics.first { $0.metric == name }?.decimalValue?.value ?? "") ?? 0 }
            let day = String(format: "%04d-%02d-%02d", row.startTime.year, row.startTime.month, row.startTime.day)
            return PlayCrashDay(day: day, crashRate: value("crashRate"), userPerceived: value("userPerceivedCrashRate"))
        }
    }

    private func send(_ url: URL, json body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await tokens.token())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw PlayError.http(status, String(decoding: data, as: UTF8.self)) }
        return data
    }
}
