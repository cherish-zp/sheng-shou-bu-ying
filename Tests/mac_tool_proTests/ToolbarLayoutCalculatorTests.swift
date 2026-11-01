import XCTest

/// TDD: 工具条宽度计算 —— 按钮数量决定窗口宽度，杜绝按钮溢出被裁（对标浮引：
/// 20 槽全部完整可见）。规格：padding 8×2 + 手柄 22+6 + 每槽 28+4（末槽无尾距）。
final class ToolbarLayoutCalculatorTests: XCTestCase {

    func test_zeroButtons_handleAndPaddingOnly() {
        let width = ToolbarLayoutCalculator.totalWidth(buttonCount: 0)
        XCTAssertEqual(width, 8 + 22 + 6 + 8, "无按钮时仅手柄 + 两侧留白")
    }

    func test_twentyButtons_formulaValue() {
        // 20 槽：8 + 22 + 6 + 20×(28+4) − 4 + 8 = 680
        let width = ToolbarLayoutCalculator.totalWidth(buttonCount: 20)
        XCTAssertEqual(width, 680)
    }

    func test_twentyFourButtons_coversAllOurSlots() {
        // 24 槽（我方全部槽位）= 808pt，完整容纳含确认按钮的尾部
        let width = ToolbarLayoutCalculator.totalWidth(buttonCount: 24)
        XCTAssertEqual(width, 808)
    }

    func test_negativeCount_clampedToZero() {
        XCTAssertEqual(ToolbarLayoutCalculator.totalWidth(buttonCount: -3),
                       ToolbarLayoutCalculator.totalWidth(buttonCount: 0))
    }
}
