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

    func test_emptyPanelWidth() {
        XCTAssertEqual(TransferShelfLayoutSpec.emptyPanelWidth, 210, accuracy: 0.1)
    }

    /// 大图标竖排卡：图标居中上部 + 名称 + 副标题。
    func test_itemIconSize() {
        XCTAssertEqual(TransferShelfLayoutSpec.itemIconSize, 52, accuracy: 0.1)
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

    // MARK: - 大图标竖排卡

    func test_cardSizeIsPortraitTile() {
        XCTAssertEqual(TransferShelfLayoutSpec.cardSize.width, 124, accuracy: 0.1)
        XCTAssertEqual(TransferShelfLayoutSpec.cardSize.height, 116, accuracy: 0.1,
                       "竖排卡：大图标上部居中 + 名称 + 副标题，数据横向摆放")
    }

    func test_itemCornerRadius() {
        XCTAssertEqual(TransferShelfLayoutSpec.itemCornerRadius, 12, accuracy: 0.1,
                       "大卡圆角相应放大")
    }

    func test_itemClearButtonSize() {
        XCTAssertEqual(TransferShelfLayoutSpec.itemClearButtonSize, 14, accuracy: 0.1)
    }

    // MARK: - 单行横向流（高度恒定、宽度 clamp、溢出滚动）

    /// 内容总宽：N 张卡 + 卡间距 + 两侧 padding；不足空态宽时抬到空态宽。
    func test_contentWidth() {
        XCTAssertEqual(TransferShelfLayoutSpec.contentWidth(itemCount: 1),
                       TransferShelfLayoutSpec.emptyPanelWidth, accuracy: 0.1,
                       "1 张卡不足空态宽，抬到空态宽")
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

    /// 高度恒定：无论多少条目都是单行（溢出靠横向滚动，不再换行拉高）。
    func test_panelSize_heightIsConstantSingleRow() {
        let expectedH = TransferShelfLayoutSpec.headerHeight
            + TransferShelfLayoutSpec.contentTopGap
            + TransferShelfLayoutSpec.cardSize.height
            + TransferShelfLayoutSpec.panelPadding
        XCTAssertEqual(TransferShelfLayoutSpec.panelSize(itemCount: 1, screenWidth: 1512).height,
                       expectedH, accuracy: 0.1)
        XCTAssertEqual(TransferShelfLayoutSpec.panelSize(itemCount: 9, screenWidth: 1512).height,
                       expectedH, accuracy: 0.1, "20 条也不换行——单行横向流")
        XCTAssertEqual(TransferShelfLayoutSpec.panelSize(itemCount: 20, screenWidth: 1512).height,
                       expectedH, accuracy: 0.1)
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
