import Foundation
import Security

/// The user's API key and vendor number. Kept in the Keychain, only on this device unless the Mac app's user
/// chooses iCloud Keychain: it can read the account's sales, so it never leaves the iPhone except to Apple.
public struct Account: Codable, Equatable, Sendable {
    public var issuer: String
    public var keyID: String
    public var privateKeyPEM: String
    public var vendorNumber: String

    public init(issuer: String, keyID: String, privateKeyPEM: String, vendorNumber: String) {
        self.issuer = issuer
        self.keyID = keyID
        self.privateKeyPEM = privateKeyPEM
        self.vendorNumber = vendorNumber
    }

    public var key: APIKey { APIKey(issuer: issuer, keyID: keyID, privateKeyPEM: privateKeyPEM) }
}

public enum KeyStore {
    public static let service = "studio.oxdeploy.appsales.account"

    public static func load() -> Account? {
        Keychain.load(service).flatMap { try? JSONDecoder().decode(Account.self, from: $0) }
    }

    /// `inICloud` lets iCloud Keychain carry it to the user's other Macs; the iPhone app never does.
    public static func save(_ account: Account, inICloud: Bool = false) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        Keychain.save(data, service: service, inICloud: inICloud)
    }

    public static func delete() { Keychain.delete(service) }
}

/// One generic password per service, either only on this device or in iCloud Keychain. On the Mac the iCloud ones
/// live in the data protection keychain, the others where they always were, so both places are searched.
public enum Keychain {
    /// The user's choice on the Mac to keep the keys in iCloud Keychain, for keys saved later; the iPhone never sets it.
    public static var keysInICloud: Bool {
        get { UserDefaults.standard.bool(forKey: "keys.iCloud") }
        set { UserDefaults.standard.set(newValue, forKey: "keys.iCloud") }
    }

    public static func load(_ service: String) -> Data? {
        for extra in places {
            var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            query.merge(extra) { $1 }
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data { return data }
        }
        return nil
    }

    /// Whether the item is in iCloud Keychain.
    public static func isInICloud(_ service: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrSynchronizable as String: true, kSecUseDataProtectionKeychain as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public static func save(_ data: Data, service: String, inICloud: Bool) {
        delete(service)
        var item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecValueData as String: data]
        if inICloud {
            item[kSecAttrSynchronizable as String] = true
            item[kSecUseDataProtectionKeychain as String] = true
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        } else {
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        SecItemAdd(item as CFDictionary, nil)
    }

    public static func delete(_ service: String) {
        for extra in places {
            var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
            query.merge(extra) { $1 }
            SecItemDelete(query as CFDictionary)
        }
    }

    /// iCloud Keychain first, then the device-only item as it was always saved.
    private static var places: [[String: Any]] { [
        [kSecAttrSynchronizable as String: true, kSecUseDataProtectionKeychain as String: true],
        [:],
    ] }
}
