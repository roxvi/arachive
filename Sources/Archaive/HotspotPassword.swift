import Foundation
import Security

enum HotspotPassword {
    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "local.archaive.hotspot-password",
         kSecAttrAccount as String: name]
    }

    static func read(for name: String) throws -> String? {
        var attributes = query(name)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else { throw failure(status) }
        return password
    }

    static func save(_ password: String, for name: String) throws {
        let attributes = query(name)
        let update = [kSecValueData as String: Data(password.utf8)]
        var status = SecItemUpdate(attributes as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var entry = attributes.merging(update) { _, new in new }
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(entry as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }

    private static func failure(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Could not access the hotspot password in Keychain (\(status))."])
    }
}
