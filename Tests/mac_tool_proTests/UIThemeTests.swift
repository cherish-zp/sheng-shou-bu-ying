import XCTest
import AppKit

/// TDD: UITheme 深色主题应用 —— 全部功能窗口必须呈现深色面板（对标浮引），
/// 杜绝"内容层深色但窗口本体/滚动区仍白"的半吊子换肤。
final class UIThemeTests: XCTestCase {

    func test_applyDarkWindow_setsBackgroundAndDarkAppearance() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.backgroundColor = .white
        window.appearance = NSAppearance(named: .aqua)

        UITheme.applyDark(window)

        XCTAssertEqual(window.backgroundColor, UITheme.panelBackground)
        XCTAssertEqual(window.appearance?.name, .darkAqua)
    }

    func test_darkScroll_disablesWhiteBackgroundAndClearsTable() {
        let scroll = NSScrollView()
        let table = NSTableView()
        table.usesAlternatingRowBackgroundColors = true
        scroll.documentView = table

        UITheme.darkScroll(scroll)

        XCTAssertFalse(scroll.drawsBackground, "滚动区白底必须关闭")
        XCTAssertEqual(scroll.backgroundColor, .clear)
        XCTAssertEqual(table.backgroundColor, .clear)
        XCTAssertFalse(table.usesAlternatingRowBackgroundColors, "交替行浅色条与深色主题冲突")
    }

    func test_toolbarTokens_areDark() {
        // 亮度按“叠在黑底上”的合成结果计（半透明色的深浅由 alpha 参与）
        func compositedBrightness(_ c: NSColor) -> Double {
            let rgb = c.usingColorSpace(.deviceRGB)!
            let a = rgb.alphaComponent
            return (rgb.redComponent * a + rgb.greenComponent * a + rgb.blueComponent * a) / 3
        }
        XCTAssertLessThan(compositedBrightness(UITheme.toolbarBackground), 0.3, "工具条底必须是深色")
        XCTAssertLessThan(compositedBrightness(UITheme.toolbarControl), 0.3)
        XCTAssertLessThan(compositedBrightness(UITheme.chromeText), 1.0)
        XCTAssertGreaterThan(compositedBrightness(UITheme.chromeText), 0.5, "chrome 文字应为亮色")
    }

    func test_categoryColor_stableForSameKey() {
        XCTAssertEqual(UITheme.categoryColor(for: "screenshot"),
                       UITheme.categoryColor(for: "screenshot"))
        XCTAssertEqual(UITheme.categoryPalette.count, 8, "浮引 8 色分类板")
    }
}
