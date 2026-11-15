import Foundation
import Security

/// The user's API key and vendor number. Kept in the Keychain, only on this device (not in iCloud Keychain,
/// not in backups): it can read the account's sales, so it never leaves the iPhone except to Apple.
public struct Account: Codable, Equatable, Sendable {
    public var issuer: String
    public var keyID: String
    public var privateKeyPEM: String
    public var vendorNumber: String

    public var key: APIKey { APIKey(issuer: issuer, keyID: keyID, privateKeyPEM: privateKeyPEM) }
}

public enum KeyStore {
    private static let service = "studio.oxdeploy.appsales.account"

    public static func load() -> Account? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    public static func save(_ account: Account) {
        delete()
        guard let data = try? JSONEncoder().encode(account) else { return }
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                   kSecValueData as String: data]
        SecItemAdd(item as CFDictionary, nil)
    }

    public static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}
