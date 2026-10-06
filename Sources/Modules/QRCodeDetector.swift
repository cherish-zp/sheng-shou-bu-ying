import CoreGraphics
import CoreImage

/// 二维码检测：对截图 CGImage 用 CoreImage CIDetector(QRCodeDetector) 检出内容。
/// 纯函数（无状态），输入输出均为值类型，可单测（测试用 CIQRCodeGenerator 生成已知图闭环）。
public enum QRCodeDetector {

    /// 检测图片中的全部二维码内容（按检出顺序返回）。无命中返回空数组。
    public static func detect(in image: CGImage) -> [String] {
        guard let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) else { return [] }
        let features = detector.features(in: CIImage(cgImage: image))
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }

    /// 二维码内容摘要：超出 maxCount 时截断加省略号（用于 Toast 文案）。
    public static func summary(of content: String, maxCount: Int = 16) -> String {
        guard content.count > maxCount else { return content }
        return String(content.prefix(maxCount)) + "…"
    }
}
