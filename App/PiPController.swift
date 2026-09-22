import SwiftUI
import AVKit

final class PiPSurface: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var sampleLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
}
struct PiPPreview: UIViewRepresentable {
    let controller: PiPController
    func makeUIView(context: Context) -> PiPSurface { controller.surface }
    func updateUIView(_ uiView: PiPSurface, context: Context) {}
}
final class PiPController: NSObject, ObservableObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    let surface = PiPSurface()
    @Published var active = false
    @Published var message = ""
    private var controller: AVPictureInPictureController?
    private var timer: Timer?
    private var format: CMVideoFormatDescription?
    private var paused = false
    private var foreground = true
    override init() {
        super.init()
        surface.sampleLayer.videoGravity = .resizeAspect
        surface.backgroundColor = .black
        guard AVPictureInPictureController.isPictureInPictureSupported() else { message = "当前设备不支持画中画"; return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:surface.sampleLayer, playbackDelegate:self)
        controller = AVPictureInPictureController(contentSource:source)
        controller?.delegate = self
        controller?.requiresLinearPlayback = true
        timer = Timer.scheduledTimer(withTimeInterval:0.5, repeats:true) { [weak self] _ in self?.render() }
    }
    deinit { timer?.invalidate() }
    func setForeground(_ value: Bool) { foreground = value }
    func start() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode:.moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            paused = false; render(); controller?.invalidatePlaybackState()
            guard controller?.isPictureInPicturePossible == true else {
                message = "请先停留在首页预览约两秒，再点开启。若仍无效，请检查系统画中画设置并用真机测试。"; return
            }
            controller?.startPictureInPicture()
        } catch { message = "无法开启画中画：\(error.localizedDescription)" }
    }
    func stop() { controller?.stopPictureInPicture() }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { active = true; message = "画中画已开启" }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        active = false; message = "画中画已关闭"
        try? SharedStore.shared.setEnabled(false)
        try? AVAudioSession.sharedInstance().setActive(false, options:.notifyOthersOnDeactivation)
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        message = "画中画启动失败：\(error.localizedDescription)"
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true) // The root preview is always available when iOS restores the app.
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        paused = !playing
        // System pause is also a reliable way to stop API activity. Play never silently re-arms capture.
        if !playing { try? SharedStore.shared.setEnabled(false) }
        controller?.invalidatePlaybackState()
    }
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start:.negativeInfinity, duration:.positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { paused }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) { completionHandler() }

    private func render() {
        guard foreground || active, !paused else { return }
        autoreleasepool {
            let store = SharedStore.shared
            let size = CGSize(width:960, height:540)
            let rendererFormat = UIGraphicsImageRendererFormat(); rendererFormat.scale = 1; rendererFormat.opaque = true
            let image = UIGraphicsImageRenderer(size:size, format:rendererFormat).image { ctx in
                UIColor(red:0.055, green:0.075, blue:0.12, alpha:1).setFill(); ctx.fill(CGRect(origin:.zero, size:size))
                func text(_ value: String, y: CGFloat, size: CGFloat, color: UIColor = .white, height: CGFloat = 64) {
                    let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
                    (value as NSString).draw(in:CGRect(x:32, y:y, width:896, height:height), withAttributes:[
                        .font:UIFont.systemFont(ofSize:size, weight:.medium), .foregroundColor:color, .paragraphStyle:paragraph])
                }
                text("CW·聊伴  /  \(store.settings.selectedContact.name)", y:24, size:28, color:.systemTeal)
                if let result = store.usableResult(), let analysis = result.analysis {
                    text("可能意图：\(analysis.intent)  ·  风险 \(Int(analysis.danger))/9", y:78, size:30)
                    text("建议：\(analysis.action)", y:128, size:28, color:.lightGray)
                    for (index, reply) in analysis.replies.prefix(3).enumerated() {
                        text("\(index+1). \(reply.text)", y:192 + CGFloat(index) * 94, size:31, height:88)
                    }
                    text("候选请在「聊伴」键盘中点选  ·  \(result.createdAt.formatted(date:.omitted, time:.shortened))", y:495, size:20, color:.lightGray, height:32)
                } else {
                    let status = !store.control.isEnabled ? "分析已暂停；请回主程序开启" : store.status.isFresh ? store.status.message : "等待屏幕广播，请确认已启动录屏"
                    text(status, y:132, size:34, height:180)
                    text("将小窗放在识别区域之外，避免遮挡聊天", y:380, size:25, color:.lightGray)
                }
            }
            var pixel: CVPixelBuffer?
            let attributes: [String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String:true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String:true, kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
            guard CVPixelBufferCreate(kCFAllocatorDefault, 960, 540, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixel) == kCVReturnSuccess,
                  let pixel, let cg = image.cgImage else { return }
            CVPixelBufferLockBaseAddress(pixel, [])
            guard let context = CGContext(data:CVPixelBufferGetBaseAddress(pixel), width:960, height:540, bitsPerComponent:8,
                bytesPerRow:CVPixelBufferGetBytesPerRow(pixel), space:CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
                CVPixelBufferUnlockBaseAddress(pixel, []); return
            }
            context.draw(cg, in:CGRect(origin:.zero, size:size))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            if format == nil { CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault, imageBuffer:pixel, formatDescriptionOut:&format) }
            guard let format else { return }
            var timing = CMSampleTimingInfo(duration:CMTime(value:1, timescale:2), presentationTimeStamp:CMTime(seconds:CACurrentMediaTime(), preferredTimescale:600), decodeTimeStamp:.invalid)
            var sample: CMSampleBuffer?
            guard CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault, imageBuffer:pixel, formatDescription:format,
                sampleTiming:&timing, sampleBufferOut:&sample) == noErr, let sample else { return }
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary:true) as? [NSMutableDictionary] {
                attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
            }
            if surface.sampleLayer.status == .failed { surface.sampleLayer.flush() }
            if surface.sampleLayer.isReadyForMoreMediaData { surface.sampleLayer.enqueue(sample) }
        }
    }
}
