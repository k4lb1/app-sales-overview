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
    /// The developer's public answer, if there is one. Optional, so reviews kept before it existed still load.
    public var response: ReviewResponse?
}

/// A developer's public answer to a review. Apple shows it under the review once it's published.
public struct ReviewResponse: Codable, Hashable, Sendable {
    public var id: String
    public var body: String
    /// "PUBLISHED" or "PENDING_PUBLISH".
    public var state: String
    public var date: Date

    public init(id: String, body: String, state: String, date: Date) {
        self.id = id
        self.body = body
        self.state = state
        self.date = date
    }
}

extension Client {
    /// The newest reviews, each with the developer's answer if there is one.
    public func reviews(appID: String, limit: Int = 20) async throws -> [Review] {
        let data = try await get("/v1/apps/\(appID)/customerReviews",
                                 query: ["limit": "\(limit)", "sort": "-createdDate", "include": "response"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let page = try decoder.decode(ReviewPage.self, from: data)
        let responses = Dictionary((page.included ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return page.data.map { resource in
            let a = resource.attributes
            let response = resource.relationships?.response?.data.flatMap { responses[$0.id] }.map { included in
                ReviewResponse(id: included.id, body: included.attributes.responseBody ?? "", state: included.attributes.state ?? "",
                               date: included.attributes.lastModifiedDate ?? a.createdDate)
            }
            return Review(id: resource.id, appID: appID, rating: a.rating, title: a.title ?? "", body: a.body ?? "",
                          nickname: a.reviewerNickname ?? "", territory: a.territory ?? "", date: a.createdDate, response: response)
        }
    }

    /// Answers a review publicly; an answer that's already there is replaced. Apple publishes it after a short check.
    public func respond(to reviewID: String, with text: String) async throws -> ReviewResponse {
        let data = try await post("/v1/customerReviewResponses", json: [
            "data": ["type": "customerReviewResponses", "attributes": ["responseBody": text],
                     "relationships": ["review": ["data": ["type": "customerReviews", "id": reviewID]]]],
        ])
        struct Created: Decodable { let data: ReviewPage.Included }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let created = try decoder.decode(Created.self, from: data).data
        return ReviewResponse(id: created.id, body: created.attributes.responseBody ?? text, state: created.attributes.state ?? "PENDING_PUBLISH",
                              date: created.attributes.lastModifiedDate ?? .now)
    }

    public func deleteResponse(_ id: String) async throws {
        _ = try await delete("/v1/customerReviewResponses/\(id)")
    }
}

private struct ReviewPage: Decodable {
    var data: [Resource]
    var included: [Included]?
    struct Resource: Decodable {
        var id: String
        var attributes: Attributes
        var relationships: Relationships?
    }
    struct Relationships: Decodable {
        struct Link: Decodable {
            struct Target: Decodable { var id: String }
            var data: Target?
        }
        var response: Link?
    }
    struct Included: Decodable {
        var id: String
        var attributes: ResponseAttributes
    }
    struct ResponseAttributes: Decodable {
        var responseBody: String?
        var lastModifiedDate: Date?
        var state: String?
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
