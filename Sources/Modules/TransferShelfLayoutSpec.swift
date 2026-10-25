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


    /// 面板发丝描边宽度与条目圆角（苹果风细节）。
    public static let panelHairlineWidth: CGFloat = 1
    public static let itemCornerRadius: CGFloat = 12

    /// 卡片图标边长。
    public static let itemIconSize: CGFloat = 32

    /// 条目右上角单独删除按钮。
    public static let itemClearButtonSize: CGFloat = 12
    public static let itemClearButtonOffset: CGFloat = 2

    /// UI ③ 头部栏高度（标题 + 条目计数 + 清空按钮）。
    public static let headerHeight: CGFloat = 26

    /// UI ④ 空态面板高度：容纳图标 + 主文案 + 辅助文案的居中排版。
    public static let emptyPanelHeight: CGFloat = 88

    /// UI ④ 呼出动画微缩放起点（1.0 落定）。
    public static let appearScale: CGFloat = 0.96

    /// UI ④ 热区拖拽提示胶囊尺寸。
    public static let hotHintSize = NSSize(width: 118, height: 28)

    /// UI ① 毛玻璃材质（圆角裁剪由容器 layer 负责）。
    public static let panelMaterial: NSVisualEffectView.Material = .hudWindow

    /// 卡片尺寸（图标 + 单行名称，浮引/Yoink 式方形卡片）。
    public static let cardSize = NSSize(width: 84, height: 84)

    /// 面板两侧距屏幕边缘的最小留白：面板拉长也不贴边。
    public static let screenSideMargin: CGFloat = 24

    /// 头部栏与卡片区之间的纵向间距。
    public static let contentTopGap: CGFloat = 8

    /// 屏幕可用宽度内一行最多容纳多少张卡片（至少 1；不超过条目数）。
    public static func cardsPerRow(itemCount: Int, screenWidth: CGFloat) -> Int {
        let usable = screenWidth - screenSideMargin * 2 - panelPadding * 2
        let perRow = Int(floor((usable + itemSpacing) / (cardSize.width + itemSpacing)))
        return max(1, min(perRow, max(1, itemCount)))
    }

    /// 面板尺寸（卡片横向流）：宽 = 实际列数宽度（至少空态宽，天然不超屏），
    /// 高 = 头部 + 行数 × 卡片（不设上限——内容放不下靠换行兜底，永不滚动）。
    public static func panelSize(itemCount: Int, screenWidth: CGFloat) -> CGSize {
        if itemCount <= 0 {
            return CGSize(width: emptyPanelWidth, height: emptyPanelHeight)
        }
        let perRow = cardsPerRow(itemCount: itemCount, screenWidth: screenWidth)
        let columns = min(itemCount, perRow)
        let rows = Int(ceil(Double(itemCount) / Double(perRow)))
        let width = max(emptyPanelWidth,
                        panelPadding * 2 + CGFloat(columns) * cardSize.width + CGFloat(columns - 1) * itemSpacing)
        let content = CGFloat(rows) * cardSize.height + CGFloat(rows - 1) * itemSpacing
        return CGSize(width: width,
                      height: headerHeight + contentTopGap + content + panelPadding)
    }


    /// 拖出条目时的预览图像帧（NSDraggingItem 必须设置非零 frame，否则崩溃）。
    public static let dragImageFrame: NSRect = NSRect(x: 0, y: 0, width: 64, height: 64)
}
