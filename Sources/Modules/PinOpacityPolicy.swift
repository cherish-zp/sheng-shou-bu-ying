import Foundation

/// 贴图不透明度策略（纯逻辑）：菜单 slider 与「恢复不透明」共用口径。
/// 范围 20%-100%，默认 100%；窗口 alphaValue = 百分比 / 100。
public enum PinOpacityPolicy {

    /// slider 最小百分比。
    public static let minPercent: Double = 20
    /// slider 最大百分比（= 完全不透明）。
    public static let maxPercent: Double = 100
    /// 默认（新建贴图 / 恢复不透明）。
    public static let defaultPercent: Double = 100

    /// 夹取到 20-100。
    public static func clamped(_ percent: Double) -> Double {
        Swift.min(Swift.max(percent, minPercent), maxPercent)
    }

    /// 百分比 → NSWindow.alphaValue（0-1）。
    public static func alphaValue(for percent: Double) -> Double {
        clamped(percent) / 100.0
    }

    /// 当前 alphaValue（0-1）→ 百分比（菜单 slider 初始值）。
    public static func percent(fromAlphaValue alpha: Double) -> Double {
        clamped(alpha * 100.0)
    }
}
