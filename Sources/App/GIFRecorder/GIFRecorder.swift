import AppKit
import ImageIO
import UniformTypeIdentifiers

/// GIF 录制：每 0.5s 截取主屏一帧，停止后编码为 GIF 存到桌面。
final class GIFRecorder: NSObject {
    static let shared = GIFRecorder()
    private var frames: [CGImage] = []
    private var timer: Timer?
    private var isRecording = false

    var isRunning: Bool { isRecording }

    func start() {
        guard !isRecording else { return }
        frames = []
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let image = CGDisplayCreateImage(CGMainDisplayID()) else { return }
            // 半分辨率控制体积
            let ctx = CGContext(data: nil, width: image.width / 2, height: image.height / 2,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width / 2, height: image.height / 2))
            if let frame = ctx.makeImage() { self?.frames.append(frame) }
            if self?.frames.count == 120 { self?.stop() }  // 上限 60 秒
        }
    }

    func stop() {
        guard isRecording else { return }
        timer?.invalidate()
        timer = nil
        isRecording = false
        encodeAndSave()
    }

    private func encodeAndSave() {
        guard !frames.isEmpty else { return }
        let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("录制-\(Int(Date().timeIntervalSince1970)).gif")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.5],
        ]
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { return }
        DiagLog.write("GIFRecorder: saved \(url.path) frames=\(frames.count)")
    }
}
