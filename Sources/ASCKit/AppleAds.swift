import CryptoKit
import Foundation

/// Access to an Apple Ads account through the Apple Ads Platform API: the client, team and key IDs that Apple shows
/// after the public key is uploaded under Account Settings > API, the private key that belongs to it, and the ad
/// account chosen after connecting. Kept in the Keychain like the other keys.
public struct AdsAccount: Codable, Equatable, Sendable {
    public var clientID: String
    public var teamID: String
    public var keyID: String
    public var privateKeyPEM: String
    public var adAccountID: Int?

    public init(clientID: String, teamID: String, keyID: String, privateKeyPEM: String, adAccountID: Int? = nil) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.teamID = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.keyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.privateKeyPEM = privateKeyPEM
        self.adAccountID = adAccountID
    }

    /// A new key pair: the private half stays here, the public half goes into the Apple Ads settings.
    public static func newKey() -> (privatePEM: String, publicPEM: String) {
        let key = P256.Signing.PrivateKey()
        return (key.pemRepresentation, key.publicKey.pemRepresentation)
    }

    /// The public half of a private key, to show again.
    public static func publicKey(of privatePEM: String) -> String? {
        (try? P256.Signing.PrivateKey(pemRepresentation: privatePEM))?.publicKey.pemRepresentation
    }
}

/// One campaign on one day.
public struct AdsCampaignDay: Codable, Hashable, Sendable {
    public var day: String
    public var campaignID: Int
    public var campaign: String
    /// The promoted app's Apple ID.
    public var appID: String
    public var spend: Double
    public var currency: String
    public var impressions: Int
    public var taps: Int
    /// Installs from taps and views together.
    public var installs: Int
    public var newDownloads: Int

    public init(day: String, campaignID: Int, campaign: String, appID: String, spend: Double, currency: String,
                impressions: Int, taps: Int, installs: Int, newDownloads: Int) {
        self.day = day
        self.campaignID = campaignID
        self.campaign = campaign
        self.appID = appID
        self.spend = spend
        self.currency = currency
        self.impressions = impressions
        self.taps = taps
        self.installs = installs
        self.newDownloads = newDownloads
    }
}

public enum AdsError: Error, LocalizedError {
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .http(let status, let body): "Apple Ads answered HTTP \(status): \(body.prefix(300))"
        }
    }
}

/// Talks to the Apple Ads Platform API (api.ads.apple.com/v1): a token from Apple's OAuth server for the signed
/// client secret, the ad accounts the key may see, and the daily campaign report.
public actor AdsClient {
    private let account: AdsAccount
    private let signer: P256.Signing.PrivateKey
    private var current: (token: String, until: Date)?
    private static let base = "https://api.ads.apple.com/v1"

    public init(account: AdsAccount) throws {
        self.account = account
        signer = try P256.Signing.PrivateKey(pemRepresentation: account.privateKeyPEM)
    }

    /// The ad accounts this key may read, with their names.
    public func adAccounts() async throws -> [(id: Int, name: String)] {
        struct Answer: Decodable {
            struct Result: Decodable {
                struct ACL: Decodable {
                    struct Account: Decodable { let id: Int; let name: String? }
                    let adAccount: Account
                }
                let acls: [ACL]?
            }
            let result: Result
        }
        let answer = try JSONDecoder().decode(Answer.self, from: try await send("/acls", adAccount: nil))
        return (answer.result.acls ?? []).map { ($0.adAccount.id, $0.adAccount.name ?? String($0.adAccount.id)) }
    }

    /// Each campaign's figures per day from `start` to `end` ("yyyy-MM-dd", at most 90 days apart), in UTC days.
    public func campaignDays(adAccount: Int, start: String, end: String) async throws -> [AdsCampaignDay] {
        struct Money: Decodable { let amount: String; let currency: String }
        struct Metrics: Decodable {
            let date: String?
            let localSpend: Money?
            let impressions: Int?
            let taps: Int?
            let totalInstalls: Int?
            let totalNewDownloads: Int?
        }
        struct Answer: Decodable {
            struct Result: Decodable {
                struct Row: Decodable {
                    struct Campaign: Decodable { let id: Int; let name: String?; let promotedObjectId: String? }
                    let metadata: Campaign
                    let granularMetrics: [Metrics]?
                }
                let rows: [Row]?
            }
            struct Pagination: Decodable { let totalCount: Int? }
            let result: Result?
            let pagination: Pagination?
        }
        var days: [AdsCampaignDay] = [], offset = 0
        while true {
            let body: [String: Any] = [
                "timeRange": ["start": start, "end": end, "timeZone": "UTC", "granularity": "DAILY"],
                "pagination": ["offset": offset, "pageSize": 1000],
            ]
            let answer = try JSONDecoder().decode(Answer.self, from: try await send("/reports/apps/campaigns/query", adAccount: adAccount, json: body))
            let rows = answer.result?.rows ?? []
            for row in rows {
                for metrics in row.granularMetrics ?? [] {
                    guard let date = metrics.date else { continue }
                    days.append(AdsCampaignDay(day: String(date.prefix(10)), campaignID: row.metadata.id, campaign: row.metadata.name ?? "",
                                               appID: row.metadata.promotedObjectId ?? "", spend: Double(metrics.localSpend?.amount ?? "") ?? 0,
                                               currency: metrics.localSpend?.currency ?? "", impressions: metrics.impressions ?? 0,
                                               taps: metrics.taps ?? 0, installs: metrics.totalInstalls ?? 0,
                                               newDownloads: metrics.totalNewDownloads ?? 0))
                }
            }
            offset += rows.count
            guard !rows.isEmpty, offset < answer.pagination?.totalCount ?? 0 else { return days }
        }
    }

    private func send(_ path: String, adAccount: Int?, json body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: Self.base + path)!)
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        if let adAccount { request.setValue("adAccountId=\(adAccount)", forHTTPHeaderField: "X-AP-Context") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AdsError.http(status, String(decoding: data, as: UTF8.self)) }
        return data
    }

    /// An access token for an hour, asked for with a client secret signed by the account's key.
    private func token() async throws -> String {
        if let current, current.until > .now.addingTimeInterval(60) { return current.token }
        var request = URLRequest(url: URL(string: "https://appleid.apple.com/auth/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "grant_type", value: "client_credentials"), URLQueryItem(name: "client_id", value: account.clientID),
                           URLQueryItem(name: "client_secret", value: try clientSecret()), URLQueryItem(name: "scope", value: "searchadsorg")]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AdsError.http(status, String(decoding: data, as: UTF8.self)) }
        struct Answer: Decodable { let access_token: String; let expires_in: Double }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        current = (answer.access_token, .now.addingTimeInterval(answer.expires_in))
        return answer.access_token
    }

    /// The JWT Apple's OAuth server takes as the client secret: ES256, the key ID in the header, the team as issuer and
    /// the client as subject; an hour is plenty, Apple allows up to 180 days.
    func clientSecret(now: Date = .now) throws -> String {
        let issued = Int(now.timeIntervalSince1970)
        let header = ["alg": "ES256", "kid": account.keyID]
        let payload: [String: Any] = ["iss": account.teamID, "sub": account.clientID, "aud": "https://appleid.apple.com",
                                      "iat": issued, "exp": issued + 3600]
        let signingInput = try Client.base64URL(JSONSerialization.data(withJSONObject: header))
            + "." + Client.base64URL(JSONSerialization.data(withJSONObject: payload))
        let signature = try signer.signature(for: Data(signingInput.utf8))
        return signingInput + "." + Client.base64URL(signature.rawRepresentation)
    }
}

public enum AdsKeyStore {
    public static let service = "studio.oxdeploy.ads.account"

    public static func load() -> AdsAccount? {
        Keychain.load(service).flatMap { try? JSONDecoder().decode(AdsAccount.self, from: $0) }
    }

    public static func save(_ account: AdsAccount, inICloud: Bool = false) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        Keychain.save(data, service: service, inICloud: inICloud)
    }

    public static func delete() { Keychain.delete(service) }
}
