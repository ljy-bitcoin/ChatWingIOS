import Foundation
import Security

enum Keys {
    private static func query(_ account: String) throws -> [String: Any] {
        if !SharedStore.shared.usesAppGroup {
            return try SharedKeychain.query(service: "ChatWing.API", account: account)
        }
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String,
              !group.contains("$(") else {
            throw ChatWingError.message("Keychain 分组未配置，请检查签名。")
        }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "ChatWing.API", kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: group]
    }
    static func get(_ account: String) throws -> String {
        var q = try query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw ChatWingError.message("无法读取密钥（Keychain \(status)），请解锁手机并检查共享签名。")
        }
        return value
    }
    static func set(_ account: String, value: String) throws {
        let q = try query(account)
        if value.isEmpty {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ChatWingError.message("删除密钥失败：\(status)") }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = q; insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let created = SecItemAdd(insert as CFDictionary, nil)
            guard created == errSecSuccess else { throw ChatWingError.message("保存密钥失败：\(created)") }
        } else if status != errSecSuccess { throw ChatWingError.message("更新密钥失败：\(status)") }
    }
}
