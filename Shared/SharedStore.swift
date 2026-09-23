import Foundation
import Darwin
import Security

// App Group files use flock. Keychain fallback stores whole records atomically;
// session UUIDs reject stale results, and concurrent control writes are last-writer-wins.
final class SharedStore {
    static let shared = SharedStore()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let localLock = NSRecursiveLock()
    private lazy var root: URL? = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }()
    var usesAppGroup: Bool { root != nil }
    var available: Bool { root != nil || (try? SharedKeychain.group()) != nil }
    func read<T: Decodable>(_ file: String, as: T.Type) -> T? {
        localLock.lock(); defer { localLock.unlock() }
        let data: Data
        if let root {
            guard let loaded = try? Data(contentsOf: root.appendingPathComponent(file)) else { return nil }
            data = loaded
        } else {
            guard let loaded = try? SharedKeychain.read(file) else { return nil }
            data = loaded
        }
        return try? decoder.decode(T.self, from: data)
    }
    func write<T: Encodable>(_ value: T, to file: String) throws {
        localLock.lock(); defer { localLock.unlock() }
        guard let root else {
            try SharedKeychain.write(encoder.encode(value), account: file)
            return
        }
        let url = root.appendingPathComponent(file)
        try encoder.encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        var mutableURL = url; try? mutableURL.setResourceValues(resource)
    }
    func delete(_ file: String) {
        localLock.lock(); defer { localLock.unlock() }
        if let root { try? FileManager.default.removeItem(at: root.appendingPathComponent(file)) }
        else { try? SharedKeychain.delete(file) }
    }
    var settings: Settings { read("settings.json", as: Settings.self) ?? Settings() }
    var control: SessionControl { read("control.json", as: SessionControl.self) ?? SessionControl() }
    var status: BroadcastStatus { read("broadcast.json", as: BroadcastStatus.self) ?? BroadcastStatus() }
    var result: ResultEnvelope? { read("result.json", as: ResultEnvelope.self) }
    var foreground: Bool { read("presence.json", as: AppPresence.self)?.foreground ?? true }
    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> SessionControl {
        localLock.lock(); defer { localLock.unlock() }
        guard let root else {
            let value = SessionControl(id: UUID(), enabled: enabled,
                expiresAt: enabled ? Date().addingTimeInterval(600) : .distantPast)
            try write(value, to: "control.json")
            delete("result.json")
            return value
        }
        let fd = Darwin.open(root.appendingPathComponent("control.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ChatWingError.message("无法写入会话状态") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw ChatWingError.message("会话锁定失败") }
        defer { flock(fd, LOCK_UN) }
        let value = SessionControl(id: UUID(), enabled: enabled, expiresAt: enabled ? Date().addingTimeInterval(600) : .distantPast)
        try write(value, to: "control.json")
        delete("result.json")
        return value
    }
    func usableResult() -> ResultEnvelope? {
        guard let result, result.isUsable(control: control, contactID: settings.selectedContact.id) else { return nil }
        if result.source == "live" && !status.isFresh { return nil }
        return result
    }
}

// Uses only groups accepted by Security.framework; never treats a profile as authority.
// Kept in this file so the keyboard target also compiles the bridge.
enum SharedKeychain {
    private static let lock = NSRecursiveLock()
    private static var cachedGroup: String?
    private static let service = "ChatWing.Shared.v1"

    static func group() throws -> String {
        lock.lock(); defer { lock.unlock() }
        if let cachedGroup { return cachedGroup }
        // A re-signer may leave TEAM.* as the default group. Do not create
        // a default item first: explicitly validate concrete profile candidates.
        // Profile values are candidates only; Security.framework remains the authority.
        var candidates: [String] = []
        let bundles = [Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()]
        for bundle in bundles {
            let url = bundle.appendingPathComponent("embedded.mobileprovision")
            guard let data = try? Data(contentsOf: url),
                  let start = data.range(of: Data("<?xml".utf8)),
                  let end = data.range(of: Data("</plist>".utf8),
                    in: start.lowerBound..<data.endIndex),
                  let plist = try? PropertyListSerialization.propertyList(
                    from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil),
                  let profile = plist as? [String: Any],
                  let entitlements = profile["Entitlements"] as? [String: Any] else { continue }
            if let identifier = entitlements["application-identifier"] as? String,
               !identifier.contains("*") { candidates.append(identifier) }
            if let groups = entitlements["keychain-access-groups"] as? [String] {
                candidates.append(contentsOf: groups.filter { !$0.contains("*") })
            }
        }
        // Without a profile, read an existing default probe if available.
        if candidates.isEmpty {
            let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "ChatWing.SigningProbe.v1",
                kSecAttrAccount as String: Bundle.main.bundleIdentifier ?? "ChatWing",
                kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(probe as CFDictionary, &result)
            if status == errSecSuccess, let attrs = result as? [String: Any],
               let actual = attrs[kSecAttrAccessGroup as String] as? String,
               !actual.contains("*") { candidates.append(actual) }
        }
        var failures: [String] = []
        var seen = Set<String>()
        for candidate in candidates where !candidate.isEmpty && seen.insert(candidate).inserted {
            var validation: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: "bridge-probe",
                kSecAttrAccessGroup as String: candidate,
                kSecValueData as String: Data([1]),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let added = SecItemAdd(validation as CFDictionary, nil)
            guard added == errSecSuccess || added == errSecDuplicateItem else {
                failures.append("写入 \(added)")
                continue
            }
            validation.removeValue(forKey: kSecValueData as String)
            validation.removeValue(forKey: kSecAttrAccessible as String)
            let readable = SecItemCopyMatching(validation as CFDictionary, nil)
            guard readable == errSecSuccess else {
                failures.append("读取 \(readable)")
                continue
            }
            cachedGroup = candidate
            return candidate
        }
        let detail = failures.isEmpty ? "未找到具体分组" : failures.joined(separator: "、")
        throw ChatWingError.message("兼容版2：钥匙串权限验证失败（\(detail)）。需检查重签名权限，重复保存无效。")
    }

    static func query(service: String = "ChatWing.Shared.v1", account: String) throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrAccessGroup as String: try group()]
    }
    static func read(_ account: String) throws -> Data? {
        var q = try query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw error(status) }
        return result as? Data
    }
    static func write(_ data: Data, account: String) throws {
        guard data.count <= 512 * 1024 else { throw ChatWingError.message("共享内容过大，请缩短聊天文本。") }
        let q = try query(account: account)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(q as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = q
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
            if status == errSecDuplicateItem { status = SecItemUpdate(q as CFDictionary, update as CFDictionary) }
        }
        guard status == errSecSuccess else { throw error(status) }
    }
    static func delete(_ account: String) throws {
        let status = SecItemDelete(try query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
    }
    private static func error(_ status: OSStatus) -> ChatWingError {
        .message("签名共享访问失败（\(status)）。请确认主程序和扩展使用同一账号签名，并保留钥匙串共享权限。")
    }
}
