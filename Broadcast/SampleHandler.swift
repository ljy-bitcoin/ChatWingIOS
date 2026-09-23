import ReplayKit
import ImageIO

// ReplayKit lives in a separate process. All pipeline state is confined to `worker`.
final class SampleHandler: RPBroadcastSampleHandler {
    private let worker = DispatchQueue(label:"ChatWing.Broadcast", qos:.userInitiated)
    private let admission = NSLock()
    private var queued = false
    private var nextFrame = Date.distantPast
    private var heartbeat: DispatchSourceTimer?
    private let store = SharedStore.shared
    private let ocr = OCRReader()
    private var running = false
    private var paused = false
    private var message = "录屏已启动，等待开启分析"
    private var sessionID: UUID?
    private var revision: UUID?
    private var observed = ""
    private var stableCount = 0
    private var completed = ""
    private var taskFingerprint: String?
    private var requestID: UUID?
    private var analysisTask: Task<Void, Never>?
    private var nextRequest = Date.distantPast
    private var failureCount = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        worker.async {
            guard self.store.read("settings.json", as: Settings.self) != nil else {
                self.finishBroadcastWithError(NSError(domain: "ChatWing.Signing", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "录屏扩展无法读取主程序配置。请先在聊伴保存配置；若仍失败，当前签名没有提供可用的跨扩展共享权限。"] ))
                return
            }
            self.running = true
            let timer = DispatchSource.makeTimerSource(queue:self.worker)
            timer.schedule(deadline:.now(), repeating:2)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                if !self.store.control.isEnabled { self.invalidate(clearResult:true); self.message = "分析已暂停，请在主程序开启" }
                self.publishStatus()
            }
            self.heartbeat = timer; timer.resume()
        }
    }
    override func broadcastPaused() {
        worker.async { self.paused = true; self.invalidate(clearResult:true); self.message = "系统录屏已暂停"; self.publishStatus() }
    }
    override func broadcastResumed() {
        worker.async { self.paused = false; self.message = "录屏已恢复"; self.publishStatus() }
    }
    override func broadcastFinished() {
        worker.sync {
            running = false; invalidate(clearResult:true); heartbeat?.cancel(); heartbeat = nil
            message = "录屏已停止"; publishStatus()
        }
    }
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        admission.lock()
        guard !queued, Date() >= nextFrame else { admission.unlock(); return }
        queued = true; nextFrame = Date().addingTimeInterval(max(1, store.settings.frameInterval)); admission.unlock()
        let raw = (CMGetAttachment(sampleBuffer, key:RPVideoSampleOrientationKey as CFString, attachmentModeOut:nil) as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue:raw) ?? .up
        worker.async {
            defer { self.admission.lock(); self.queued = false; self.admission.unlock() }
            autoreleasepool { self.consume(pixel, orientation:orientation) }
        }
    }
    private func consume(_ pixel: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        guard running, !paused else { return }
        let control = store.control, settings = store.settings
        guard control.isEnabled else { invalidate(clearResult:true); message = "分析已暂停"; return }
        if control.id != sessionID || settings.revision != revision {
            invalidate(clearResult:true); sessionID = control.id; revision = settings.revision
            nextRequest = .distantPast; failureCount = 0
        }
        guard !store.foreground else { message = "请切换到选定联系人的聊天页面"; return }
        do {
            let snapshot = try ocr.read(pixelBuffer:pixel, orientation:orientation, crop:settings.crop)
            if settings.requireTitleMatch && !TextLogic.matchesTitle(snapshot.title, contact:settings.selectedContact) {
                invalidate(clearResult:true); message = "标题未匹配「\(settings.selectedContact.name)」，未调用模型"; return
            }
            guard !snapshot.messages.isEmpty else { invalidate(clearResult:true); message = "当前区域没有可识别消息"; return }
            let fingerprint = TextLogic.fingerprint(snapshot.messages, contactID:settings.selectedContact.id)
            if observed != fingerprint {
                observed = fingerprint; stableCount = 1
                analysisTask?.cancel(); analysisTask = nil; taskFingerprint = nil
                requestID = nil
                store.delete("result.json")
                message = "等待画面稳定"; return
            }
            stableCount += 1
            guard stableCount >= 2 else { return }
            if fingerprint == completed { message = "画面未变化，无需重复调用"; return }
            guard analysisTask == nil, Date() >= nextRequest else { return }
            let capturedSession = control.id, capturedRevision = settings.revision
            let capturedRequest = UUID(); requestID = capturedRequest
            nextRequest = Date().addingTimeInterval(max(6, settings.requestInterval))
            taskFingerprint = fingerprint; message = "正在分析"
            try store.write(ResultEnvelope(sessionID:control.id, contactID:settings.selectedContact.id,
                contactName:settings.selectedContact.name, messages:snapshot.messages, status:"正在分析…"), to:"result.json")
            analysisTask = Task { [weak self] in
                do {
                    let result = try await AnalysisService().analyze(messages:snapshot.messages, settings:settings)
                    try Task.checkCancellation()
                    self?.worker.async { [weak self] in
                        guard let self, self.accepts(capturedSession, revision:capturedRevision, fingerprint:fingerprint, request:capturedRequest) else { return }
                        self.analysisTask = nil; self.taskFingerprint = nil; self.completed = fingerprint; self.failureCount = 0
                        self.message = "分析完成"
                        try? self.store.write(ResultEnvelope(sessionID:capturedSession, contactID:settings.selectedContact.id,
                            contactName:settings.selectedContact.name, messages:snapshot.messages, analysis:result, status:"分析完成"), to:"result.json")
                    }
                } catch is CancellationError { /* A newer frame/session owns the state now. */ }
                catch {
                    let message = (error as? URLError) != nil ? "网络请求失败，请检查网络和接口地址。" : error.localizedDescription
                    self?.worker.async { [weak self] in
                        guard let self, self.accepts(capturedSession, revision:capturedRevision, fingerprint:fingerprint, request:capturedRequest) else { return }
                        self.analysisTask = nil; self.taskFingerprint = nil; self.failureCount += 1
                        self.nextRequest = Date().addingTimeInterval(min(120, 15 * pow(2, Double(min(3, self.failureCount - 1)))))
                        self.message = message
                        try? self.store.write(ResultEnvelope(sessionID:capturedSession, contactID:settings.selectedContact.id,
                            contactName:settings.selectedContact.name, messages:snapshot.messages, status:message), to:"result.json")
                    }
                }
            }
        } catch { invalidate(clearResult:true); message = "文字识别失败，请检查识别区域" }
    }
    private func accepts(_ session: UUID, revision: UUID, fingerprint: String, request: UUID) -> Bool {
        running && !paused && store.control.isEnabled && store.control.id == session &&
        store.settings.revision == revision && observed == fingerprint && taskFingerprint == fingerprint && requestID == request
    }
    private func invalidate(clearResult: Bool) {
        analysisTask?.cancel(); analysisTask = nil; taskFingerprint = nil
        requestID = nil
        observed = ""; completed = ""; stableCount = 0
        if clearResult { store.delete("result.json") }
    }
    private func publishStatus() {
        try? store.write(BroadcastStatus(running:running, paused:paused, updatedAt:Date(), message:message), to:"broadcast.json")
    }
}
