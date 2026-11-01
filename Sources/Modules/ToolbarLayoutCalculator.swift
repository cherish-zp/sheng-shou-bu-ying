import CoreGraphics
import Foundation

/// 工具条宽度计算（纯逻辑，TDD）：按钮数量 → 窗口内容宽度。
/// 根因背景：窗口宽度曾固定 690pt，按钮扩到 24 个后尾部（分享/关闭/确认）被裁掉——
/// 对标浮引按槽位动态计宽。
public enum ToolbarLayoutCalculator {
    public static let padding: CGFloat = 8
    public static let handleWidth: CGFloat = 22
    public static let handleGap: CGFloat = 6
    public static let buttonSize: CGFloat = 28
    public static let buttonGap: CGFloat = 4

    /// 按钮数量 → 工具条内容宽度（pt）。
    public static func totalWidth(buttonCount: Int) -> CGFloat {
        let count = max(0, buttonCount)
        return padding * 2 + handleWidth + handleGap
            + CGFloat(count) * (buttonSize + buttonGap)
            - (count > 0 ? buttonGap : 0)
    }
}
