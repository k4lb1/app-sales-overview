import Foundation
import Security

/// A Google Cloud service account's JSON key, as downloaded from the Cloud Console. The account is invited into
/// the Play Console; its key stays on the device and is used only to get short-lived tokens from Google.
public struct ServiceAccount: Codable, Equatable, Sendable {
    public var clientEmail: String
    /// PKCS#8 PEM, as in the JSON file.
    public var privateKey: String
    public var tokenURI: String

    enum CodingKeys: String, CodingKey {
        case clientEmail = "client_email", privateKey = "private_key", tokenURI = "token_uri"
    }

    public init(json: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: json)
    }
}

public enum PlayError: Error, CustomStringConvertible {
    case http(Int, String)
    case key(String)

    public var description: String {
        switch self {
        case .http(let status, let body): "HTTP \(status): \(body.prefix(400))"
        case .key(let reason): reason
        }
    }
}

/// Short-lived access tokens for the service account: a JWT signed with its RSA key (RS256) is exchanged at Google's
/// token endpoint (RFC 7523). A token lasts an hour and is kept until a few minutes before it runs out.
actor TokenSource {
    private let account: ServiceAccount
    private let key: SecKey
    private let scopes: String
    private var current: (token: String, until: Date)?

    init(account: ServiceAccount, scopes: [String]) throws {
        self.account = account
        key = try RSAKey.privateKey(pem: account.privateKey)
        self.scopes = scopes.joined(separator: " ")
    }

    func token() async throws -> String {
        if let current, current.until > .now.addingTimeInterval(300) { return current.token }
        var request = URLRequest(url: URL(string: account.tokenURI)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(try assertion())".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw PlayError.http(status, String(decoding: data, as: UTF8.self)) }
        struct Answer: Decodable { let access_token: String; let expires_in: Double }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        current = (answer.access_token, .now.addingTimeInterval(answer.expires_in))
        return answer.access_token
    }

    func assertion(now: Date = .now) throws -> String {
        let issued = Int(now.timeIntervalSince1970)
        let header = ["alg": "RS256", "typ": "JWT"]
        let claims: [String: Any] = ["iss": account.clientEmail, "scope": scopes, "aud": account.tokenURI,
                                     "iat": issued, "exp": issued + 3600]
        let input = try JWT.base64URL(JSONSerialization.data(withJSONObject: header, options: .sortedKeys)) + "."
            + JWT.base64URL(JSONSerialization.data(withJSONObject: claims, options: .sortedKeys))
        return input + "." + JWT.base64URL(try RSAKey.sign(Data(input.utf8), with: key))
    }
}

enum JWT {
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The service account's RSA key. Google hands it out as PKCS#8; Security wants the PKCS#1 key inside it.
enum RSAKey {
    static func privateKey(pem: String) throws -> SecKey {
        let base64 = pem.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: base64) else { throw PlayError.key("The key in the JSON file can't be read.") }
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                         kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(try pkcs1(der) as CFData, attributes as CFDictionary, &error) else {
            throw PlayError.key("The key in the JSON file isn't an RSA private key.")
        }
        return key
    }

    static func sign(_ data: Data, with key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &error) else {
            throw PlayError.key("Signing with the key failed.")
        }
        return signature as Data
    }

    /// PKCS#8 is SEQUENCE { INTEGER version, SEQUENCE algorithm, OCTET STRING key }; the octet string is the PKCS#1 key.
    /// A key that's already PKCS#1 (SEQUENCE { INTEGER, INTEGER modulus, … }) is returned as it is.
    static func pkcs1(_ der: Data) throws -> Data {
        var reader = DERReader(Array(der))
        let outer = try reader.element(0x30)
        var inner = DERReader(outer)
        _ = try inner.element(0x02)
        guard inner.next == 0x30 else { return der }
        _ = try inner.element(0x30)
        return Data(try inner.element(0x04))
    }
}

/// Just enough DER to take the key out of PKCS#8: tag, length (short or long form), contents.
struct DERReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var next: UInt8? { offset < bytes.count ? bytes[offset] : nil }

    mutating func element(_ tag: UInt8) throws -> [UInt8] {
        guard next == tag, offset + 1 < bytes.count else { throw PlayError.key("The key in the JSON file has an unexpected form.") }
        offset += 1
        var length = Int(bytes[offset])
        offset += 1
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count <= 4, offset + count <= bytes.count else { throw PlayError.key("The key in the JSON file has an unexpected form.") }
            length = bytes[offset..<offset + count].reduce(0) { $0 << 8 | Int($1) }
            offset += count
        }
        guard offset + length <= bytes.count else { throw PlayError.key("The key in the JSON file is cut short.") }
        defer { offset += length }
        return Array(bytes[offset..<offset + length])
    }
}
