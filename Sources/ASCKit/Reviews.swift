import Foundation

public struct Review: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var appID: String
    public var rating: Int
    public var title: String
    public var body: String
    public var nickname: String
    public var territory: String
    public var date: Date
}

extension Client {
    public func reviews(appID: String, limit: Int = 20) async throws -> [Review] {
        let data = try await get("/v1/apps/\(appID)/customerReviews", query: ["limit": "\(limit)", "sort": "-createdDate"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ReviewPage.self, from: data).data.map { resource in
            let a = resource.attributes
            return Review(id: resource.id, appID: appID, rating: a.rating, title: a.title ?? "", body: a.body ?? "",
                          nickname: a.reviewerNickname ?? "", territory: a.territory ?? "", date: a.createdDate)
        }
    }
}

private struct ReviewPage: Decodable {
    var data: [Resource]
    struct Resource: Decodable {
        var id: String
        var attributes: Attributes
    }
    struct Attributes: Decodable {
        var rating: Int
        var title: String?
        var body: String?
        var reviewerNickname: String?
        var territory: String?
        var createdDate: Date
    }
}
