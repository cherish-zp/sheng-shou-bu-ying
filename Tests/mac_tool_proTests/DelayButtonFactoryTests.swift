import XCTest
import AppKit

/// TDD: 延时截图按钮工厂 —— 修复 attributedTitle 被 title="" 覆盖清空，
/// 导致延时子面板三个按钮在深色底上"隐形"。同时锁定对标浮引的样式：
/// 深色底 + 白色 "3s/5s/10s" 标签。
final class DelayButtonFactoryTests: XCTestCase {

    func test_attributedTitleSurvivesAndShowsSeconds() {
        let button = ToolbarButtonFactory.delayButton(seconds: 5, target: nil, action: nil)
        XCTAssertEqual(button.attributedTitle.string, "5s", "标签不得被 title 覆盖清空")
    }

    func test_allDelaySeconds_labeled() {
        for seconds in [3, 5, 10] {
            let button = ToolbarButtonFactory.delayButton(seconds: seconds, target: nil, action: nil)
            XCTAssertEqual(button.attributedTitle.string, "\(seconds)s")
        }
    }

    func test_labelIsDarkOnGlass() {
        let button = ToolbarButtonFactory.delayButton(seconds: 3, target: nil, action: nil)
        let color = button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let rgb = color?.usingColorSpace(.deviceRGB)
        XCTAssertLessThan(rgb?.redComponent ?? 1, 0.4, "浅玻璃面板上标签应为深色")
    }

    func test_tagCarriesSeconds() {
        XCTAssertEqual(ToolbarButtonFactory.delayButton(seconds: 10, target: nil, action: nil).tag, 10)
    }
}
