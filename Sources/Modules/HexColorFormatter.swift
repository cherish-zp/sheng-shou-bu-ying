import CoreGraphics
import Foundation

/// 颜色格式化（纯逻辑）：rgba 分量 / CGColor → #RRGGBB 与 rgb(r, g, b) 文本。
/// 取色器放大镜色值条、复制 Toast 与颜色历史共用。
public enum HexColorFormatter {

    /// rgba 分量（0-1 浮点）→ #RRGGBB（大写十六进制）。
    /// 分量 ×255 后四舍五入并夹取到 0-255（1.2 → 255、-0.1 → 0、0.5 → 128）；alpha 忽略。
    public static func hexString(red: Double, green: Double, blue: Double) -> String {
        String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// rgba 分量（0-1 浮点）→ "rgb(r, g, b)"，口径与 hexString 一致。
    public static func rgbString(red: Double, green: Double, blue: Double) -> String {
        "rgb(\(byte(red)), \(byte(green)), \(byte(blue)))"
    }

    /// CGColor → #RRGGBB；分量不足 3 个按灰度处理（r=g=b），无法解析返回 nil。
    public static func hexString(from color: CGColor) -> String? {
        guard let rgb = rgbComponents(of: color) else { return nil }
        return hexString(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// CGColor → "rgb(r, g, b)"。
    public static func rgbString(from color: CGColor) -> String? {
        guard let rgb = rgbComponents(of: color) else { return nil }
        return rgbString(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    // MARK: - 内部

    /// 提取前三个分量；灰度（1-2 分量）展开为 r=g=b。alpha 一律忽略。
    private static func rgbComponents(of color: CGColor) -> (red: Double, green: Double, blue: Double)? {
        guard let comps = color.components, !comps.isEmpty else { return nil }
        if comps.count < 3 {
            let gray = Double(comps[0])
            return (gray, gray, gray)
        }
        return (Double(comps[0]), Double(comps[1]), Double(comps[2]))
    }

    /// 分量 → 0-255 字节：×255 后四舍五入（.toNearestOrAwayFromZero）并夹取。
    private static func byte(_ value: Double) -> Int {
        let scaled = (value * 255).rounded()
        return Int(Swift.min(Swift.max(scaled, 0), 255))
    }
}
