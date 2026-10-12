import AppKit
import CoreGraphics

/// 截图捕获服务：在显示覆盖层之前抓取各屏幕画面，避免把覆盖层本身截进去。
/// 使用 CoreGraphics CGDisplayCreateImage（macOS 13+ 兼容）。
final class ScreenCaptureService {

    /// 诊断开关（默认关）：亮度带分析对每块屏做一次全图解码（5K 屏 ~59MB 临时分配 +
    /// 主线程数十 ms），仅排查 HDR"截图变暗"类问题时启用：
    /// `defaults write com.zp.shengshoubuying diag.captureLuminance -bool YES`
    public static let luminanceDiagnosticsKey = "diag.captureLuminance"

    public static func luminanceDiagnosticsEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: luminanceDiagnosticsKey)
    }

    /// 捕获所有活跃显示器，返回 [(显示器ID, 画面, 屏幕Frame)]。
    func captureAllDisplays() -> [(displayID: CGDirectDisplayID, image: CGImage, frame: CGRect)] {
        var maxDisplays: UInt32 = 8
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        CGGetActiveDisplayList(maxDisplays, &displayIDs, &maxDisplays)

        let logLuminance = Self.luminanceDiagnosticsEnabled()
        var results: [(CGDirectDisplayID, CGImage, CGRect)] = []
        for id in displayIDs.prefix(Int(maxDisplays)) {
            guard let image = CGDisplayCreateImage(id) else { continue }
            if logLuminance {
                logBandLuminance(image, displayID: id)
            }
            let bounds = CGDisplayBounds(id)
            results.append((id, image, bounds))
        }
        return results
    }

    /// 诊断：记录捕获画面上/下 10% 带的平均亮度。
    /// HDR/EDR 色调映射类问题会表现为上下带亮度系统性差异（纵向渐变），
    /// 该日志与 screencapture 参照 dump（dumpCaptureReference）配合定位"截图变暗"类问题。
    private func logBandLuminance(_ image: CGImage, displayID: CGDirectDisplayID) {
        let w = image.width
        let h = image.height
        guard w > 0, h >= 20 else { return }
        let bytesPerRow = w * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * h)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        func bandMean(_ range: Range<Int>) -> Double {
            var sum = 0.0
            var n = 0
            let strideX = max(1, w / 100) * 4
            for y in range {
                let row = y * bytesPerRow
                for x in stride(from: w / 4 * 4, to: min(w * 3 / 4 * 4, bytesPerRow - 4), by: strideX) {
                    let off = row + x
                    sum += (Double(pixels[off]) + Double(pixels[off + 1]) + Double(pixels[off + 2])) / 3.0
                    n += 1
                }
            }
            return n > 0 ? sum / Double(n) : 0
        }

        let band = max(1, h / 10)
        let top = bandMean(0..<band)
        let bottom = bandMean((h - band)..<h)
        DiagLog.write(String(format: "CaptureLuminance display=%d top=%.1f bottom=%.1f delta=%.1f",
                             displayID, top, bottom, bottom - top))
    }

    /// 请求屏幕录制权限（macOS 10.15+）。首次调用会弹系统授权对话框。
    @discardableResult
    func requestPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        }
        return true
    }
}
