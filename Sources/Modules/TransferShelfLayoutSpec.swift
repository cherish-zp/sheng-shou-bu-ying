import Foundation
import AppKit

/// 文件中转站布局规格：顶部面板、条目尺寸、动画参数。
public enum TransferShelfLayoutSpec {
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
    public static let emptyPanelWidth: CGFloat = 420
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


    /// 面板发丝描边宽度与条目圆角（苹果风细节）。
    public static let panelHairlineWidth: CGFloat = 1
    public static let itemCornerRadius: CGFloat = 10

    /// 紧凑行卡图标：面板高度锁定空态 88pt，卡片区 42pt。
    public static let itemIconSize: CGFloat = 20

    /// 条目右上角删除按钮（hover 显示）。
    public static let itemClearButtonSize: CGFloat = 14

    /// UI ③ 头部栏高度（标题 + 条目计数 + 清空按钮）。
    public static let headerHeight: CGFloat = 26

    /// UI ④ 空态面板高度：容纳图标 + 主文案 + 辅助文案的居中排版。
    public static let emptyPanelHeight: CGFloat = 88

    /// UI ④ 呼出动画微缩放起点（1.0 落定）。
    public static let appearScale: CGFloat = 0.96

    /// UI ④ 热区拖拽提示胶囊尺寸。
    public static let hotHintSize = NSSize(width: 118, height: 28)

    /// 紧凑行卡尺寸：图标左 + 名称/副标题右两行，高 42 恰入 88 高面板；
    /// 数据横向摆放，溢出横向滚动。
    public static let cardSize = NSSize(width: 190, height: 42)

    /// 面板两侧距屏幕边缘的最小留白：面板拉长也不贴边。
    public static let screenSideMargin: CGFloat = 24

    /// 头部栏与卡片区之间的纵向间距。
    public static let contentTopGap: CGFloat = 8

    /// N 张卡的内容总宽（含两侧 padding）；不足空态宽时抬到空态宽。
    public static func contentWidth(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return emptyPanelWidth }
        let width = panelPadding * 2
            + CGFloat(itemCount) * cardSize.width
            + CGFloat(itemCount - 1) * itemSpacing
        return max(emptyPanelWidth, width)
    }

    /// 面板尺寸：高度**永远等于空态高 88**（用户定案：加文件不改高度），
    /// 宽度 = 内容总宽 clamp 到 [空态宽, 屏宽 - 2×侧边距]——溢出横向滚动。
    public static func panelSize(itemCount: Int, screenWidth: CGFloat) -> CGSize {
        if itemCount <= 0 {
            return CGSize(width: emptyPanelWidth, height: emptyPanelHeight)
        }
        let maxWidth = screenWidth - screenSideMargin * 2
        let width = min(contentWidth(itemCount: itemCount), maxWidth)
        return CGSize(width: width, height: emptyPanelHeight)
    }


    /// 拖出条目时的预览图像帧（NSDraggingItem 必须设置非零 frame，否则崩溃）。
    public static let dragImageFrame: NSRect = NSRect(x: 0, y: 0, width: 64, height: 64)
}
