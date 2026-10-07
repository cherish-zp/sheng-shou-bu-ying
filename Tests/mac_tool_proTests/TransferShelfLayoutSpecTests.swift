import XCTest

/// TDD: 文件中转站布局规格 - 顶部横向面板、条目尺寸、动画参数。
final class TransferShelfLayoutSpecTests: XCTestCase {

    func test_panelHeight() {
        XCTAssertEqual(TransferShelfLayoutSpec.panelHeight, 68, accuracy: 0.1)
    }

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
        XCTAssertEqual(TransferShelfLayoutSpec.itemIconSize, 24, accuracy: 0.1)
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

    func test_verticalPanelWidth() {
        XCTAssertEqual(TransferShelfLayoutSpec.verticalPanelWidth, 180, accuracy: 0.1)
    }

    func test_verticalItemSize() {
        // 宽度自适应后条目宽度随面板宽度计算(不再固定 156);高度保持两行结构。
        XCTAssertEqual(TransferShelfLayoutSpec.verticalItemHeight, 44, accuracy: 0.1)
    }

    func test_verticalPanelHeightFitsItems() {
        let height = TransferShelfLayoutSpec.panelHeight(itemCount: 3)
        let expected = TransferShelfLayoutSpec.headerHeight + 12 + 44 * 3 + 10 * 2 + 12
        XCTAssertEqual(height, expected, accuracy: 0.1, "内容区之上要预留头部栏高度")
    }

    func test_verticalPanelHeightCappedToMax() {
        let height = TransferShelfLayoutSpec.panelHeight(itemCount: 30, maxHeight: 400)
        XCTAssertLessThanOrEqual(height, 400)
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

    func test_panelWidthClampsToMinimum() {
        let width = TransferShelfLayoutSpec.panelWidth(itemTextWidths: [4])
        XCTAssertEqual(width, 200, accuracy: 0.1, "短条目也保持 200pt 下限")
    }

    func test_panelWidthClampsToMaximum() {
        let width = TransferShelfLayoutSpec.panelWidth(itemTextWidths: [600])
        XCTAssertEqual(width, 260, accuracy: 0.1, "长条目封顶 260pt")
    }

    func test_panelWidthFitsLongestText() {
        let width = TransferShelfLayoutSpec.panelWidth(itemTextWidths: [60, 120, 90])
        let expected = min(max(120 + TransferShelfLayoutSpec.itemChromeWidth
                                + TransferShelfLayoutSpec.panelPadding * 2, 200), 260)
        XCTAssertEqual(width, expected, accuracy: 0.1, "面板宽度由最长条目文本决定")
    }

    func test_panelWidthEmptyItemsFallsBackToMinimum() {
        XCTAssertEqual(TransferShelfLayoutSpec.panelWidth(itemTextWidths: []), 200, accuracy: 0.1)
    }

    func test_itemChromeWidthCoversIconAndButtons() {
        // 8(icon leading) + 24(icon) + 8(gap) + 4(text 右间距) + 12(clear) + 2(offset) + 8(trailing)
        XCTAssertEqual(TransferShelfLayoutSpec.itemChromeWidth, 66, accuracy: 0.1)
    }

    func test_itemTextWidthMeasuresLongerTextAsWider() {
        let short = TransferShelfLayoutSpec.itemTextWidth(for: "ab", font: .systemFont(ofSize: 12))
        let long = TransferShelfLayoutSpec.itemTextWidth(
            for: String(repeating: "长文本", count: 40), font: .systemFont(ofSize: 12)
        )
        XCTAssertGreaterThan(long, short, "文本宽度测量应随内容增长(供 panelWidth 使用)")
    }

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
}
