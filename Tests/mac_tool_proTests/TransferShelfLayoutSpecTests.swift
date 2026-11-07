import XCTest

/// TDD: 文件中转站布局规格 - 贴顶横向卡片流（对标剪贴板面板语言）：
/// 大图标竖排卡、单行横向摆放、溢出横向滚动（滚轮纵转横）、面板高度恒定。
final class TransferShelfLayoutSpecTests: XCTestCase {

    // MARK: - 通用参数

    func test_itemSpacing() {
        XCTAssertEqual(TransferShelfLayoutSpec.itemSpacing, 10, accuracy: 0.1)
    }

    func test_cornerRadius() {
        XCTAssertEqual(TransferShelfLayoutSpec.cornerRadius, 20, accuracy: 0.1)
    }

    /// 空态宽 ×2（用户定案）：空态更大方，有文件后高度不变只在宽度上变长。
    func test_emptyPanelWidth() {
        XCTAssertEqual(TransferShelfLayoutSpec.emptyPanelWidth, 420, accuracy: 0.1)
    }

    /// 紧凑行卡图标：面板高度锁定空态 88pt，卡片区仅 42pt——图标回归左侧 20pt。
    func test_itemIconSize() {
        XCTAssertEqual(TransferShelfLayoutSpec.itemIconSize, 20, accuracy: 0.1)
    }

    func test_fadeDurations() {
        XCTAssertEqual(TransferShelfLayoutSpec.fadeInDuration, 0.2, accuracy: 0.001)
        XCTAssertEqual(TransferShelfLayoutSpec.fadeOutDuration, 0.25, accuracy: 0.001)
    }

    func test_topGap() {
        XCTAssertEqual(TransferShelfLayoutSpec.topGap, 4, accuracy: 0.1)
    }

    func test_slideInOffset() {
        XCTAssertEqual(TransferShelfLayoutSpec.slideInOffset, 12, accuracy: 0.1)
    }

    func test_hotZoneSize() {
        XCTAssertEqual(TransferShelfLayoutSpec.hotZoneWidth, 320, accuracy: 0.1)
        XCTAssertEqual(TransferShelfLayoutSpec.hotZoneHeight, 18, accuracy: 0.1)
    }

    func test_hotZoneHitTopCenter() {
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertTrue(TransferShelfLayoutSpec.isInHotZone(
            location: NSPoint(x: 500, y: 795), visibleFrame: frame))
    }

    func test_hotZoneMissTopLeft() {
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertFalse(TransferShelfLayoutSpec.isInHotZone(
            location: NSPoint(x: 50, y: 795), visibleFrame: frame))
    }

    func test_hotZoneMissMiddle() {
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertFalse(TransferShelfLayoutSpec.isInHotZone(
            location: NSPoint(x: 500, y: 400), visibleFrame: frame))
    }

    func test_hotZoneHitRespectsVisibleFrameOrigin() {
        let frame = NSRect(x: 100, y: 50, width: 1000, height: 800)
        XCTAssertTrue(TransferShelfLayoutSpec.isInHotZone(
            location: NSPoint(x: 600, y: 845), visibleFrame: frame))
    }

    func test_dragImageFrameIsNonZero() {
        let frame = TransferShelfLayoutSpec.dragImageFrame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertEqual(frame.width, frame.height, accuracy: 0.1)
    }

    func test_headerHeight() {
        XCTAssertEqual(TransferShelfLayoutSpec.headerHeight, 26, accuracy: 0.1)
    }

    func test_emptyPanelHeight() {
        XCTAssertEqual(TransferShelfLayoutSpec.emptyPanelHeight, 88, accuracy: 0.1,
                       "空态要容纳图标 + 主文案 + 辅助文案的居中排版")
    }

    func test_appearScale() {
        XCTAssertEqual(TransferShelfLayoutSpec.appearScale, 0.96, accuracy: 0.001,
                       "呼出动画微缩放起点")
    }

    func test_hotHintSize() {
        XCTAssertEqual(TransferShelfLayoutSpec.hotHintSize.width, 118, accuracy: 0.1)
        XCTAssertEqual(TransferShelfLayoutSpec.hotHintSize.height, 28, accuracy: 0.1)
    }

    func test_panelHairlineWidth() {
        XCTAssertEqual(TransferShelfLayoutSpec.panelHairlineWidth, 1, accuracy: 0.1)
    }

    // MARK: - 紧凑行卡（横向一排）

    func test_cardSizeIsPortraitTile() {
        XCTAssertEqual(TransferShelfLayoutSpec.cardSize.width, 190, accuracy: 0.1)
        XCTAssertEqual(TransferShelfLayoutSpec.cardSize.height, 42, accuracy: 0.1,
                       "高度锁定空态 88：header 26 + gap 8 + 卡 42 + padding 12")
    }

    func test_itemCornerRadius() {
        XCTAssertEqual(TransferShelfLayoutSpec.itemCornerRadius, 10, accuracy: 0.1)
    }

    func test_itemClearButtonSize() {
        XCTAssertEqual(TransferShelfLayoutSpec.itemClearButtonSize, 14, accuracy: 0.1)
    }

    // MARK: - 单行横向流（高度恒定、宽度 clamp、溢出滚动）

    /// 内容总宽：N 张卡 + 卡间距 + 两侧 padding；不足空态宽时抬到空态宽。
    func test_contentWidth() {
        // 1 张卡（190+24=214）不足空态宽 420 → 抬到 420
        XCTAssertEqual(TransferShelfLayoutSpec.contentWidth(itemCount: 1),
                       TransferShelfLayoutSpec.emptyPanelWidth, accuracy: 0.1)
        let expected3 = 2 * TransferShelfLayoutSpec.panelPadding
            + 3 * TransferShelfLayoutSpec.cardSize.width
            + 2 * TransferShelfLayoutSpec.itemSpacing
        XCTAssertEqual(TransferShelfLayoutSpec.contentWidth(itemCount: 3), expected3, accuracy: 0.1)
    }

    func test_panelSize_emptyUsesEmptyState() {
        let size = TransferShelfLayoutSpec.panelSize(itemCount: 0, screenWidth: 1512)
        XCTAssertEqual(size.width, TransferShelfLayoutSpec.emptyPanelWidth, accuracy: 0.1)
        XCTAssertEqual(size.height, TransferShelfLayoutSpec.emptyPanelHeight, accuracy: 0.1)
    }

    /// 高度恒定 = 空态高 88（用户定案）：加了文件高度不变，只在宽度上变长。
    func test_panelSize_heightEqualsEmptyStateAlways() {
        XCTAssertEqual(TransferShelfLayoutSpec.panelSize(itemCount: 1, screenWidth: 1512).height,
                       TransferShelfLayoutSpec.emptyPanelHeight, accuracy: 0.1)
        XCTAssertEqual(TransferShelfLayoutSpec.panelSize(itemCount: 9, screenWidth: 1512).height,
                       TransferShelfLayoutSpec.emptyPanelHeight, accuracy: 0.1)
        XCTAssertEqual(TransferShelfLayoutSpec.panelSize(itemCount: 20, screenWidth: 1512).height,
                       TransferShelfLayoutSpec.emptyPanelHeight, accuracy: 0.1,
                       "20 条也不变高——溢出横向滚动")
    }

    /// 空态高度也是 88：空态与有文件状态同高（用户强调空态好看、高度不变）。
    func test_emptyPanelHeightLocked() {
        XCTAssertEqual(TransferShelfLayoutSpec.emptyPanelHeight, 88, accuracy: 0.1)
    }

    /// 宽度：内容宽 clamp 到 [空态宽, 屏宽 - 2×侧边距]；超出部分横向滚动。
    func test_panelSize_widthHugsContent() {
        let size = TransferShelfLayoutSpec.panelSize(itemCount: 3, screenWidth: 1512)
        XCTAssertEqual(size.width, TransferShelfLayoutSpec.contentWidth(itemCount: 3), accuracy: 0.1)
    }

    func test_panelSize_widthNeverExceedsScreenMargin() {
        let size = TransferShelfLayoutSpec.panelSize(itemCount: 20, screenWidth: 800)
        XCTAssertLessThanOrEqual(
            size.width, 800 - TransferShelfLayoutSpec.screenSideMargin * 2 + 0.1,
            "面板再长也不越过屏幕两侧留白（溢出滚动）")
    }

    /// 滚轮纵转横：横向滚动视图必须可复用（与剪贴板面板同一共享类）。
    func test_scrollWheelViewShared() {
        XCTAssertTrue(HorizontalScrollScrollView().isKind(of: NSScrollView.self))
    }
}
