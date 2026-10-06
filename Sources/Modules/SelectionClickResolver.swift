import CoreGraphics

/// 一次单击解析出的行为：
/// - confirmSelection：点击落在现有选区内 → 确认现有选区
/// - selectWindow：检测到有效窗口且与现有选区不同 → 以窗口 rect 为新选区
/// - ignore：无有效窗口命中 → 保持/恢复现状，绝不产生坏选区
public enum SelectionClickAction: Equatable {
    case confirmSelection
    case selectWindow(CGRect)
    case ignore
}

/// 单击判定与点击行为解析（纯函数，可单测）。
/// 供截图覆盖层在 mouseUp 区分「误单击」与「真拖拽」：
/// 误单击不再被 enforceMinimumSize 强制成 10×10 坏选区，而是点选窗口或恢复原选区。
public enum SelectionClickResolver {
    /// 位移小于该阈值（dx、dy 均小于）视为单击而非拖拽。
    public static let clickThreshold: CGFloat = 4
    /// 窗口 rect 的最小有效边长（与选区最小尺寸语义一致）。
    public static let minimumWindowSize: CGFloat = 10

    /// 判断起止点是否为单击：x/y 位移均严格小于阈值。
    /// macOS 上 NSPoint 是 CGPoint 的 typealias，两种类型可互换。
    public static func isClick(start: CGPoint, end: CGPoint, threshold: CGFloat = clickThreshold) -> Bool {
        abs(end.x - start.x) < threshold && abs(end.y - start.y) < threshold
    }

    /// 解析一次单击的行为。
    /// - Parameters:
    ///   - clickPoint: 单击落点（视图坐标）
    ///   - selection: 当前选区（可为 nil；与 windowRect 同坐标系）
    ///   - windowRect: 鼠标下检测到的窗口 rect（可为 nil，与 selection 同坐标系）
    /// 规则：点击在 selection 内 → confirmSelection；否则 windowRect 有效（≥10×10）
    /// 且 ≠ selection → selectWindow；否则 ignore。
    public static func resolve(clickPoint: CGPoint, selection: CGRect?, windowRect: CGRect?) -> SelectionClickAction {
        if let sel = selection, sel.contains(clickPoint) {
            return .confirmSelection
        }
        if let window = windowRect,
           SelectionRect.isValid(window, minimum: minimumWindowSize),
           window != selection {
            return .selectWindow(window)
        }
        return .ignore
    }
}
