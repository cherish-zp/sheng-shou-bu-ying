import Foundation
import AppKit

/// 文件中转站布局规格：顶部面板、条目尺寸、动画参数。
public enum TransferShelfLayoutSpec {
    public static let panelHeight: CGFloat = 68
    public static let itemSpacing: CGFloat = 10
    public static let panelPadding: CGFloat = 12
    public static let cornerRadius: CGFloat = 20
    public static let fadeInDuration: TimeInterval = 0.2
    public static let fadeOutDuration: TimeInterval = 0.25
    public static let topGap: CGFloat = 4
    /// 面板从顶部上方滑入的距离。
    public static let slideInOffset: CGFloat = 12
    /// 顶部热区（拖拽会话期间激活，文件拖入即呼出面板）。
    public static let hotZoneWidth: CGFloat = 320
    public static let hotZoneHeight: CGFloat = 18
    /// 空态面板宽度：面板初始 frame 与 preferredPanelSize 空态分支共用，避免魔法数分叉。
    public static let emptyPanelWidth: CGFloat = 210
    /// 判断点是否位于指定屏幕可见区域顶部中央的热区内。
    public static func isInHotZone(location: NSPoint, visibleFrame: NSRect) -> Bool {
        let rect = NSRect(
            x: visibleFrame.midX - hotZoneWidth / 2,
            y: visibleFrame.maxY - hotZoneHeight,
            width: hotZoneWidth,
            height: hotZoneHeight
        )
        return NSPointInRect(location, rect)
    }

    /// 竖向排布：面板固定宽度与横向条目尺寸（图标左 + 文件名右）。
    public static let verticalPanelWidth: CGFloat = 180
    public static let verticalItemWidth: CGFloat = 156
    public static let verticalItemHeight: CGFloat = 44

    /// 面板半透明背景不透明度（自绘圆角背景，彻底消除透明直角）。
    public static let panelBackgroundAlpha: CGFloat = 0.82

    /// UI ③ 头部栏高度（标题 + 条目计数 + 清空按钮）。
    public static let headerHeight: CGFloat = 26

    /// UI ④ 空态面板高度：容纳图标 + 主文案 + 辅助文案的居中排版。
    public static let emptyPanelHeight: CGFloat = 88

    /// UI ④ 呼出动画微缩放起点（1.0 落定）。
    public static let appearScale: CGFloat = 0.96

    /// UI ④ 热区拖拽提示胶囊尺寸。
    public static let hotHintSize = NSSize(width: 118, height: 28)

    /// UI ① 毛玻璃材质（替代旧的半透明自绘背景；圆角裁剪由容器 layer 负责）。
    public static let panelMaterial: NSVisualEffectView.Material = .hudWindow

    /// UI ⑤ 面板宽度自适应区间（由最长条目文本决定，clamp 到此区间）。
    public static let minPanelWidth: CGFloat = 200
    public static let maxPanelWidth: CGFloat = 260

    /// 条目固定占位（图标 + 间距 + 删除按钮等非文本部分）：
    /// 8(icon leading) + 24(icon) + 8(gap) + 4(text 右间距) + 12(clear) + 2(offset) + 8(trailing)。
    public static let itemChromeWidth: CGFloat = 66

    /// 条目名称文本宽度测量（供 panelWidth 计算自适应宽度）。
    public static func itemTextWidth(for text: String, font: NSFont) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        return attributed.size().width
    }

    /// 面板宽度 = 最长条目文本 + 条目固定占位 + 面板左右内边距，clamp 到 [min, max]。
    public static func panelWidth(itemTextWidths: [CGFloat]) -> CGFloat {
        guard let longest = itemTextWidths.max() else { return minPanelWidth }
        let content = longest + itemChromeWidth + panelPadding * 2
        return min(max(content, minPanelWidth), maxPanelWidth)
    }

    /// 面板高度：头部栏 + 条目内容区（随条目数增长，封顶 maxHeight）。
    public static func panelHeight(itemCount: Int, maxHeight: CGFloat = 400) -> CGFloat {
        let content = verticalItemHeight * CGFloat(itemCount) + itemSpacing * CGFloat(max(0, itemCount - 1))
        return min(headerHeight + panelPadding * 2 + content, maxHeight)
    }

    /// 面板发丝描边宽度与条目圆角（苹果风细节）。
    public static let panelHairlineWidth: CGFloat = 1
    public static let itemCornerRadius: CGFloat = 12

    /// 条目图标边长（此前内联两处 24）。
    public static let itemIconSize: CGFloat = 24

    /// 条目右上角单独删除按钮。
    public static let itemClearButtonSize: CGFloat = 12
    public static let itemClearButtonOffset: CGFloat = 2

    /// 拖出条目时的预览图像帧（NSDraggingItem 必须设置非零 frame，否则崩溃）。
    public static let dragImageFrame: NSRect = NSRect(x: 0, y: 0, width: 64, height: 64)
}
