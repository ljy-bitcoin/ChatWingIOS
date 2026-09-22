import Foundation
import Darwin

// Each file is atomic. Control mutations are cross-process locked; no UserDefaults cache races.
final class SharedStore {
    static let shared = SharedStore()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let localLock = NSRecursiveLock()
    private var root: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }
    var available: Bool { root != nil }
    func read<T: Decodable>(_ file: String, as: T.Type) -> T? {
        localLock.lock(); defer { localLock.unlock() }
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent(file)) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
    func write<T: Encodable>(_ value: T, to file: String) throws {
        localLock.lock(); defer { localLock.unlock() }
        guard let root else { throw ChatWingError.message("共享空间不可用，请检查三个 Target 的 App Groups 签名配置。") }
        let url = root.appendingPathComponent(file)
        try encoder.encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        var mutableURL = url; try? mutableURL.setResourceValues(resource)
    }
    func delete(_ file: String) {
        localLock.lock(); defer { localLock.unlock() }
        if let root { try? FileManager.default.removeItem(at: root.appendingPathComponent(file)) }
    }
    var settings: Settings { read("settings.json", as: Settings.self) ?? Settings() }
    var control: SessionControl { read("control.json", as: SessionControl.self) ?? SessionControl() }
    var status: BroadcastStatus { read("broadcast.json", as: BroadcastStatus.self) ?? BroadcastStatus() }
    var result: ResultEnvelope? { read("result.json", as: ResultEnvelope.self) }
    var foreground: Bool { read("presence.json", as: AppPresence.self)?.foreground ?? true }
    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> SessionControl {
        localLock.lock(); defer { localLock.unlock() }
        guard let root else { throw ChatWingError.message("共享空间不可用") }
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
