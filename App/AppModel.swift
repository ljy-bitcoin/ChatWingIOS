import SwiftUI
import PhotosUI
import ImageIO

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: Settings
    @Published var judgeKey = ""
    @Published var replyKey = ""
    @Published var notice = ""
    @Published var enabled = false
    @Published var broadcast = BroadcastStatus()
    @Published var result: ResultEnvelope?
    @Published var manualText = ""
    @Published var manualBusy = false
    @Published var photo: PhotosPickerItem?
    private var timer: Timer?
    private var manualTask: Task<Void, Never>?
    private let store = SharedStore.shared
    init() {
        settings = store.settings
        if settings.selectedContactID == nil { settings.selectedContactID = settings.contacts.first?.id }
        do {
            if store.read("settings.json", as:Settings.self) == nil { try store.write(settings, to:"settings.json") }
            judgeKey = try Keys.get("judge"); replyKey = try Keys.get("reply")
            try store.write(AppPresence(foreground:true), to:"presence.json")
        } catch { notice = error.localizedDescription }
        timer = Timer.scheduledTimer(withTimeInterval:1, repeats:true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }
    deinit { timer?.invalidate(); manualTask?.cancel() }
    func refresh() {
        enabled = store.control.isEnabled; broadcast = store.status
        result = store.result
        if let r = result, r.sessionID != store.control.id || Date().timeIntervalSince(r.createdAt) > 180 { result = nil }
    }
    @discardableResult
    func save() -> Bool {
        do {
            guard settings.crop.isValid, (settings.titleCrop ?? TitleRegion()).isValid else { throw ChatWingError.message("识别区域上下、左右边界不正确") }
            _ = try APIClient.endpoint(settings.judgeURL); _ = try APIClient.endpoint(settings.replyURL)
            guard !settings.judgeModel.isEmpty, !settings.replyModel.isEmpty, !settings.contacts.isEmpty else {
                throw ChatWingError.message("请填写模型名称，并至少保留一个联系人")
            }
            try Keys.set("judge", value:judgeKey.trimmingCharacters(in:.whitespacesAndNewlines))
            try Keys.set("reply", value:replyKey.trimmingCharacters(in:.whitespacesAndNewlines))
            settings.revision = UUID()
            try store.write(settings, to:"settings.json")
            manualTask?.cancel(); try store.setEnabled(false)
            notice = "已保存。配置变更后请重新开启分析。"; refresh(); return true
        } catch { notice = error.localizedDescription; return false }
    }
    func arm() {
        guard save() else { return }
        guard !judgeKey.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { notice = "请先填写判断接口密钥"; return }
        do { try store.setEnabled(true); notice = "已开启，持续10分钟。请启动录屏、开启画中画，再切到选定联系人。"; refresh() }
        catch { notice = error.localizedDescription }
    }
    func pause() {
        manualTask?.cancel(); manualBusy = false
        do { try store.setEnabled(false); notice = "已暂停分析。若要停止录屏，请点系统录屏指示器。"; refresh() }
        catch { notice = error.localizedDescription }
    }
    func preset(_ type: String) {
        if type == "openrouter" {
            settings.judgeMode = .jev; settings.judgeURL = "https://openrouter.ai/api/alpha/decisions"; settings.judgeModel = "typesafe/jev-1.13"
            settings.replyURL = "https://openrouter.ai/api/v1/chat/completions"; settings.replyModel = "deepseek/deepseek-chat-v3.1"
        } else if type == "typesafe" {
            settings.judgeMode = .jev; settings.judgeURL = "https://api.typesafe.ai/v1/systemone"; settings.judgeModel = "jev-latest"
        } else {
            settings.judgeMode = .compatible; settings.judgeURL = "https://api.deepseek.com/chat/completions"; settings.judgeModel = "deepseek-chat"
            settings.replyURL = settings.judgeURL; settings.replyModel = settings.judgeModel
        }
        notice = "已填入地址示例，请核对服务商当前模型名称、填写密钥，再保存。"
    }
    func runManual() {
        guard !broadcast.isFresh else { notice = "请先停止屏幕广播，再进行手动测试，避免两路同时写入结果。"; return }
        let messages = TextLogic.parseManual(manualText)
        guard !messages.isEmpty else { notice = "先粘贴聊天文字，每行以 我：或 对方：开头。"; return }
        guard save() else { return }
        do {
            let control = try store.setEnabled(true), captured = settings
            manualBusy = true; notice = "正在调用判断与回复接口…"
            manualTask = Task {
                defer { manualBusy = false; refresh() }
                do {
                    let analysis = try await AnalysisService().analyze(messages:messages, settings:captured)
                    try Task.checkCancellation()
                    guard store.control.id == control.id, store.control.isEnabled else { return }
                    try store.write(ResultEnvelope(sessionID:control.id, contactID:captured.selectedContact.id,
                        contactName:captured.selectedContact.name, messages:messages, analysis:analysis, status:"手动测试完成", source:"manual"), to:"result.json")
                    notice = "接口测试完成，可以查看三条回复。"
                } catch is CancellationError { }
                catch { if store.control.id == control.id { notice = error.localizedDescription } }
            }
        } catch { notice = error.localizedDescription }
    }
    func loadPhoto() async {
        guard let photo else { return }
        do {
            guard let data = try await photo.loadTransferable(type:Data.self) else { throw ChatWingError.message("无法读取所选图片") }
            let crop = settings.crop
            let snapshot = try await Task.detached(priority:.userInitiated) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw ChatWingError.message("图片格式不支持")
                }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                let raw = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
                return try OCRReader().read(cgImage:cg, orientation:CGImagePropertyOrientation(rawValue:raw) ?? .up,
                    crop:crop, titleCrop:settings.titleCrop ?? TitleRegion())
            }.value
            manualText = snapshot.messages.map { "\($0.label)：\($0.text)" }.joined(separator:"\n")
            notice = "识别标题：\(snapshot.title)。请核对文字和发言方，再点分析；图片尚未上传。"
        } catch { notice = error.localizedDescription }
    }
    func clearLocal() {
        pause(); manualText = ""; store.delete("result.json"); result = nil; notice = "当前识别结果已清除；联系人和密钥保留。"
    }
}
