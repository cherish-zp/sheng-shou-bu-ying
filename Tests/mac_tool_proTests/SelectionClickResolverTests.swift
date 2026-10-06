import XCTest
import CoreGraphics

/// TDD: 单击判定与点击行为解析（悬停高亮窗口 + 单击点选 / 误单击恢复）的纯函数部分。
final class SelectionClickResolverTests: XCTestCase {

    // MARK: - isClick 阈值边界

    func test_isClick_withinThreshold() {
        // 3pt 位移均小于 4pt 阈值 → 单击
        XCTAssertTrue(SelectionClickResolver.isClick(
            start: CGPoint(x: 100, y: 100), end: CGPoint(x: 103, y: 102)))
    }

    func test_isClick_atThreshold_isNotClick() {
        // 4pt 位移不严格小于阈值 → 非单击
        XCTAssertFalse(SelectionClickResolver.isClick(
            start: CGPoint(x: 100, y: 100), end: CGPoint(x: 104, y: 104)))
    }

    func test_isClick_beyondThreshold_isNotClick() {
        XCTAssertFalse(SelectionClickResolver.isClick(
            start: CGPoint(x: 100, y: 100), end: CGPoint(x: 105, y: 105)))
    }

    func test_isClick_singleAxisExceeded_isNotClick() {
        // 单轴超限即非单击
        XCTAssertFalse(SelectionClickResolver.isClick(
            start: CGPoint(x: 100, y: 100), end: CGPoint(x: 103, y: 110)))
    }

    func test_isClick_zeroMovement_isClick() {
        XCTAssertTrue(SelectionClickResolver.isClick(
            start: CGPoint(x: 50, y: 50), end: CGPoint(x: 50, y: 50)))
    }

    func test_isClick_customThreshold() {
        XCTAssertTrue(SelectionClickResolver.isClick(
            start: CGPoint(x: 0, y: 0), end: CGPoint(x: 6, y: 0), threshold: 8))
        XCTAssertFalse(SelectionClickResolver.isClick(
            start: CGPoint(x: 0, y: 0), end: CGPoint(x: 8, y: 0), threshold: 8))
    }

    // MARK: - resolve 分支

    func test_resolve_clickInsideSelection_confirmsSelection() {
        let sel = CGRect(x: 0, y: 0, width: 100, height: 100)
        let action = SelectionClickResolver.resolve(
            clickPoint: CGPoint(x: 50, y: 50),
            selection: sel,
            windowRect: CGRect(x: 200, y: 0, width: 50, height: 50))
        XCTAssertEqual(action, .confirmSelection)
    }

    func test_resolve_clickOutside_withDifferentWindow_selectsWindow() {
        let sel = CGRect(x: 0, y: 0, width: 100, height: 100)
        let window = CGRect(x: 180, y: 0, width: 80, height: 60)
        let action = SelectionClickResolver.resolve(
            clickPoint: CGPoint(x: 220, y: 30),
            selection: sel,
            windowRect: window)
        XCTAssertEqual(action, .selectWindow(window))
    }

    func test_resolve_clickOutside_noWindow_ignores() {
        let sel = CGRect(x: 0, y: 0, width: 100, height: 100)
        let action = SelectionClickResolver.resolve(
            clickPoint: CGPoint(x: 220, y: 30),
            selection: sel,
            windowRect: nil)
        XCTAssertEqual(action, .ignore)
    }

    func test_resolve_clickOutside_tooSmallWindow_ignores() {
        // 窗口 < 10×10 无效 → ignore，绝不产生坏选区
        let sel = CGRect(x: 0, y: 0, width: 100, height: 100)
        let action = SelectionClickResolver.resolve(
            clickPoint: CGPoint(x: 220, y: 30),
            selection: sel,
            windowRect: CGRect(x: 180, y: 0, width: 8, height: 8))
        XCTAssertEqual(action, .ignore)
    }

    func test_resolve_nilSelection_withWindow_selectsWindow() {
        let window = CGRect(x: 10, y: 10, width: 50, height: 50)
        let action = SelectionClickResolver.resolve(
            clickPoint: CGPoint(x: 20, y: 20),
            selection: nil,
            windowRect: window)
        XCTAssertEqual(action, .selectWindow(window))
    }

    func test_resolve_nilSelection_noWindow_ignores() {
        let action = SelectionClickResolver.resolve(
            clickPoint: CGPoint(x: 20, y: 20),
            selection: nil,
            windowRect: nil)
        XCTAssertEqual(action, .ignore)
    }

    func test_resolve_windowSameAsSelection_ignores() {
        // 检测到的窗口与当前选区相同 → 不重复确认，保持现状
        let sel = CGRect(x: 0, y: 0, width: 100, height: 100)
        let action = SelectionClickResolver.resolve(
            clickPoint: CGPoint(x: 220, y: 30),
            selection: sel,
            windowRect: sel)
        XCTAssertEqual(action, .ignore)
    }

    func test_resolve_clickNearSelectionEdge_confirmsSelection() {
        // 选区内边界附近（含）→ 确认选区
        let sel = CGRect(x: 0, y: 0, width: 100, height: 100)
        let action = SelectionClickResolver.resolve(
            clickPoint: CGPoint(x: 99.5, y: 99.5),
            selection: sel,
            windowRect: nil)
        XCTAssertEqual(action, .confirmSelection)
    }

    func test_resolve_clickJustOutsideSelection_withWindow_selectsWindow() {
        // 选区外紧邻点（CGRect.contains 右/上边界排他）→ 走窗口点选
        let sel = CGRect(x: 0, y: 0, width: 100, height: 100)
        let window = CGRect(x: 100, y: 0, width: 60, height: 60)
        let action = SelectionClickResolver.resolve(
            clickPoint: CGPoint(x: 100, y: 50),
            selection: sel,
            windowRect: window)
        XCTAssertEqual(action, .selectWindow(window))
    }
}
