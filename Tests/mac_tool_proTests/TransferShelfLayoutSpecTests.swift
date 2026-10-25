import XCTest

/// TDD: 文件中转站布局规格 - 顶部横向面板、条目尺寸、动画参数。
final class TransferShelfLayoutSpecTests: XCTestCase {


    func test_itemSpacing() {
        XCTAssertEqual(TransferShelfLayoutSpec.itemSpacing, 10, accuracy: 0.1)
    }

    func test_cornerRadius() {
        XCTAssertEqual(TransferShelfLayoutSpec.cornerRadius, 20, accuracy: 0.1)
    }

    /// 统一空态宽度魔法数：面板初始 frame 与 preferredPanelSize 空态分支都必须用它。
    func test_emptyPanelWidth() {
        XCTAssertEqual(TransferShelfLayoutSpec.emptyPanelWidth, 210, accuracy: 0.1)
    }

    /// 条目图标尺寸常量（此前 24 内联两处）。
    func test_itemIconSize() {
        XCTAssertEqual(TransferShelfLayoutSpec.itemIconSize, 32, accuracy: 0.1)
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
        let point = NSPoint(x: 500, y: 795)
        XCTAssertTrue(TransferShelfLayoutSpec.isInHotZone(location: point, visibleFrame: frame))
    }

    func test_hotZoneMissTopLeft() {
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let point = NSPoint(x: 50, y: 795)
        XCTAssertFalse(TransferShelfLayoutSpec.isInHotZone(location: point, visibleFrame: frame))
    }

    func test_hotZoneMissMiddle() {
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let point = NSPoint(x: 500, y: 400)
        XCTAssertFalse(TransferShelfLayoutSpec.isInHotZone(location: point, visibleFrame: frame))
    }

    func test_hotZoneHitRespectsVisibleFrameOrigin() {
        let frame = NSRect(x: 100, y: 50, width: 1000, height: 800)
        let point = NSPoint(x: 600, y: 845)
        XCTAssertTrue(TransferShelfLayoutSpec.isInHotZone(location: point, visibleFrame: frame))
    }

    func test_dragImageFrameIsNonZero() {
        let frame = TransferShelfLayoutSpec.dragImageFrame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
    }





    /// 毛玻璃规格:hudWindow 材质(替代旧的半透明自绘背景)。
    func test_panelMaterialIsHUDWindow() {
        XCTAssertEqual(TransferShelfLayoutSpec.panelMaterial, .hudWindow)
    }

    // MARK: - UI ③ 头部栏 / ④ 空态与动画 / ⑤ 宽度自适应

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

    // MARK: - ⑤ 宽度自适应(clamp 200–260)







    func test_panelHairlineWidth() {
        XCTAssertEqual(TransferShelfLayoutSpec.panelHairlineWidth, 1, accuracy: 0.1)
    }

    func test_itemCornerRadius() {
        XCTAssertEqual(TransferShelfLayoutSpec.itemCornerRadius, 12, accuracy: 0.1)
    }

    func test_itemClearButtonSize() {
        XCTAssertEqual(TransferShelfLayoutSpec.itemClearButtonSize, 12, accuracy: 0.1)
    }

    func test_itemClearButtonInsets() {
        XCTAssertEqual(TransferShelfLayoutSpec.itemClearButtonOffset, 2, accuracy: 0.1)
    }

    func test_dragImageFrameIsSquare() {
        let frame = TransferShelfLayoutSpec.dragImageFrame
        XCTAssertEqual(frame.width, frame.height, accuracy: 0.1)
    }

    // MARK: - 卡片横向流（换行、无滚动）

    func test_cardSizeIsSquare() {
        XCTAssertEqual(TransferShelfLayoutSpec.cardSize.width,
                       TransferShelfLayoutSpec.cardSize.height, accuracy: 0.1)
        XCTAssertEqual(TransferShelfLayoutSpec.cardSize.width, 84, accuracy: 0.1)
    }

    func test_cardsPerRow_fitsWideScreen() {
        // 1512 屏：可用 1512-48-24=1440；(1440+10)/94=15.4 → 15；条目仅 6 张 → 6
        XCTAssertEqual(TransferShelfLayoutSpec.cardsPerRow(itemCount: 6, screenWidth: 1512), 6)
    }

    func test_cardsPerRow_wrapsOnNarrowScreen() {
        // 500 屏：可用 428；(428+10)/94=4.6 → 4 张一行
        XCTAssertEqual(TransferShelfLayoutSpec.cardsPerRow(itemCount: 9, screenWidth: 500), 4)
    }

    func test_cardsPerRow_atLeastOne() {
        XCTAssertEqual(TransferShelfLayoutSpec.cardsPerRow(itemCount: 3, screenWidth: 120), 1,
                       "极窄屏也必须保证一行至少 1 张")
    }

    func test_panelSize_emptyUsesEmptyState() {
        let size = TransferShelfLayoutSpec.panelSize(itemCount: 0, screenWidth: 1512)
        XCTAssertEqual(size.width, TransferShelfLayoutSpec.emptyPanelWidth, accuracy: 0.1)
        XCTAssertEqual(size.height, TransferShelfLayoutSpec.emptyPanelHeight, accuracy: 0.1)
    }

    func test_panelSize_singleItem() {
        let size = TransferShelfLayoutSpec.panelSize(itemCount: 1, screenWidth: 1512)
        // 单张卡片内容宽 84+24=108 < 空态宽 → 宽度抬到空态宽
        XCTAssertEqual(size.width, TransferShelfLayoutSpec.emptyPanelWidth, accuracy: 0.1)
        let expectedH = TransferShelfLayoutSpec.headerHeight
            + TransferShelfLayoutSpec.contentTopGap
            + TransferShelfLayoutSpec.cardSize.height
            + TransferShelfLayoutSpec.panelPadding
        XCTAssertEqual(size.height, expectedH, accuracy: 0.1)
    }

    func test_panelSize_widthHugsColumns() {
        let size = TransferShelfLayoutSpec.panelSize(itemCount: 3, screenWidth: 1512)
        let expectedW = CGFloat(3 * 84 + 2 * 10) + 2 * TransferShelfLayoutSpec.panelPadding
        XCTAssertEqual(size.width, expectedW, accuracy: 0.1, "宽度随列数拉长")
    }

    func test_panelSize_multiRowGrowsWithoutCap() {
        // 500 宽屏 9 项 → 4 张一行 → 3 行；高度不封顶
        let size = TransferShelfLayoutSpec.panelSize(itemCount: 9, screenWidth: 500)
        let content = CGFloat(3 * 84 + 2 * 10)
        let expectedH = TransferShelfLayoutSpec.headerHeight
            + TransferShelfLayoutSpec.contentTopGap + content
            + TransferShelfLayoutSpec.panelPadding
        XCTAssertEqual(size.height, expectedH, accuracy: 0.1, "换行兜底，高度无上限")
    }

    func test_panelSize_widthNeverExceedsScreenMargin() {
        let size = TransferShelfLayoutSpec.panelSize(itemCount: 40, screenWidth: 800)
        XCTAssertLessThanOrEqual(
            size.width,
            800 - TransferShelfLayoutSpec.screenSideMargin * 2 + 0.1,
            "面板再长也不越过屏幕两侧留白"
        )
    }
}
