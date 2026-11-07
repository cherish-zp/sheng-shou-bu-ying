import AppKit
import ImageIO
import UniformTypeIdentifiers

/// GIF 录制（App 层执行）：每 0.25s 截主屏一帧（半分辨率），最长 60s 自动停；
/// 编码 GIF 存桌面。全程用户反馈：开始红框+Toast、停止保存结果 Toast——
/// 旧版全程零反馈被用户视为「功能无效」，反馈契约见 GIFExportPlan。
final class GIFRecorder: NSObject {
    static let shared = GIFRecorder()

    private var frames: [CGImage] = []
    private var startedAt: Date?
    private var timer: Timer?
    private var isRecording = false
    /// 主屏红框指示（复用录屏红框：不抢焦点纯视觉）。
    private var borderWindow: RecordingBorderWindow?

    var isRunning: Bool { isRecording }

    func start() {
        guard !isRecording else { return }
        frames = []
        startedAt = Date()
        isRecording = true
        showBorder()
        TransientHudToast.show(text: GIFExportPlan.startToast)
        captureFrame()   // 首帧立即截，不等第一个 interval
        timer = Timer.scheduledTimer(withTimeInterval: GIFExportPlan.captureInterval,
                                     repeats: true) { [weak self] _ in
            self?.captureFrame()
            if let self, self.frames.count >= GIFExportPlan.maxFrames {
                self.stop()   // 到时自动停止（旧版静默停止，现带完整保存反馈）
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        timer?.invalidate()
        timer = nil
        isRecording = false
        hideBorder()
        encodeAndSave()
    }

    // MARK: - 帧捕获

    private func captureFrame() {
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else { return }
        let size = GIFExportPlan.scaledSize(pixelWidth: image.width, pixelHeight: image.height)
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx else { return }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        if let frame = ctx.makeImage() { frames.append(frame) }
    }

    // MARK: - 编码与保存

    private func encodeAndSave() {
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        guard !frames.isEmpty else {
            TransientHudToast.show(text: GIFExportPlan.saveToast(frames: 0, duration: duration,
                                                                 success: false, fileName: ""))
            DiagLog.write("GIFRecorder: aborted, no frames captured")
            return
        }
        let fileName = GIFExportPlan.fileName(date: Date())
        let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            TransientHudToast.show(text: GIFExportPlan.saveToast(frames: frames.count,
                                                                 duration: duration,
                                                                 success: false, fileName: ""))
            return
        }
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: GIFExportPlan.gifDelayTime],
        ]
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }
        let success = CGImageDestinationFinalize(destination)
        TransientHudToast.show(text: GIFExportPlan.saveToast(frames: frames.count,
                                                             duration: duration,
                                                             success: success, fileName: fileName))
        DiagLog.write("GIFRecorder: saved=\(success) \(url.path) frames=\(frames.count) duration=\(Int(duration))s")
    }

    // MARK: - 红框指示

    private func showBorder() {
        // 红框盖「被录制的屏」= CG 主屏（NSScreen.main 随 key 窗口漂移，可能不是主屏）
        let mainDisplay = CGMainDisplayID()
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == mainDisplay
        } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        borderWindow = RecordingBorderWindow(globalRect: frame)
    }

    private func hideBorder() {
        borderWindow?.orderOut(nil)
        borderWindow = nil
    }
}
