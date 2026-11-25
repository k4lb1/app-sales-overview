import CryptoKit
import Foundation

/// The user's App Store Connect API key. Nothing else is needed: the app talks to Apple directly.
public struct APIKey: Sendable {
    public var issuer: String
    public var keyID: String
    /// The contents of the downloaded AuthKey_<keyID>.p8.
    public var privateKeyPEM: String

    public init(issuer: String, keyID: String, privateKeyPEM: String) {
        self.issuer = issuer
        self.keyID = keyID
        self.privateKeyPEM = privateKeyPEM
    }
}

public enum ASCError: Error, CustomStringConvertible {
    case http(Int, String)

    public var description: String {
        switch self {
        case .http(let status, let body): "HTTP \(status): \(body.prefix(400))"
        }
    }
}

/// Signs every request with a short-lived token (ES256 JWT, as Apple asks) and returns the raw response.
public struct Client: Sendable {
    public static let base = URL(string: "https://api.appstoreconnect.apple.com")!
    let key: APIKey
    let signer: P256.Signing.PrivateKey

    public init(key: APIKey) throws {
        self.key = key
        signer = try P256.Signing.PrivateKey(pemRepresentation: key.privateKeyPEM)
    }

    public func get(_ path: String, query: [String: String] = [:]) async throws -> Data {
        var components = URLComponents(url: Self.base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return try await get(components.url!)
    }

    /// A full URL, as Apple hands out for the next page.
    public func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ASCError.http(status, String(decoding: data, as: UTF8.self)) }
        return data
    }

    /// Sends a JSON body, for the few things the app creates (the analytics report requests).
    public func post(_ path: String, json body: [String: Any]) async throws -> Data {
        try await send("POST", path, json: body)
    }

    /// Changes a resource, e.g. store texts.
    public func patch(_ path: String, json body: [String: Any]) async throws -> Data {
        try await send("PATCH", path, json: body)
    }

    /// Removes a resource, e.g. an answer to a review.
    public func delete(_ path: String) async throws -> Data {
        try await send("DELETE", path, json: nil)
    }

    private func send(_ method: String, _ path: String, json body: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: Self.base.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ASCError.http(status, String(decoding: data, as: UTF8.self)) }
        return data
    }

    /// Valid for 20 minutes, the longest Apple allows.
    func token() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header = ["alg": "ES256", "kid": key.keyID, "typ": "JWT"]
        let payload: [String: Any] = ["iss": key.issuer, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"]
        let signingInput = try Self.base64URL(JSONSerialization.data(withJSONObject: header))
            + "." + Self.base64URL(JSONSerialization.data(withJSONObject: payload))
        let signature = try signer.signature(for: Data(signingInput.utf8))
        return signingInput + "." + Self.base64URL(signature.rawRepresentation)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
