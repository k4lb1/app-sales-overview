import CryptoKit
import Foundation
import Testing
@testable import ASCKit

/// The client secret as Apple's OAuth guide describes it; there's no Apple Ads account to try it against.
struct AppleAdsTests {
    @Test func clientSecretIsSignedWithTheKey() async throws {
        let key = AdsAccount.newKey()
        let account = AdsAccount(clientID: "SEARCHADS.client", teamID: "SEARCHADS.team", keyID: "key-1", privateKeyPEM: key.privatePEM)
        let secret = try await AdsClient(account: account).clientSecret(now: Date(timeIntervalSince1970: 1_800_000_000))
        let parts = secret.split(separator: ".").map(String.init)
        #expect(parts.count == 3)
        func decode(_ part: String) -> Data {
            var text = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while text.count % 4 != 0 { text += "=" }
            return Data(base64Encoded: text)!
        }
        let header = try JSONSerialization.jsonObject(with: decode(parts[0])) as! [String: Any]
        let claims = try JSONSerialization.jsonObject(with: decode(parts[1])) as! [String: Any]
        #expect(header["alg"] as? String == "ES256" && header["kid"] as? String == "key-1")
        #expect(claims["iss"] as? String == "SEARCHADS.team" && claims["sub"] as? String == "SEARCHADS.client")
        #expect(claims["aud"] as? String == "https://appleid.apple.com")
        #expect(claims["exp"] as? Int == 1_800_003_600)
        let publicKey = try P256.Signing.PublicKey(pemRepresentation: key.publicPEM)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: decode(parts[2]))
        #expect(publicKey.isValidSignature(signature, for: Data((parts[0] + "." + parts[1]).utf8)))
        #expect(AdsAccount.publicKey(of: key.privatePEM) == key.publicPEM)
    }
}
