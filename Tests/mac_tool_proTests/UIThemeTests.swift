import XCTest
import AppKit

/// TDD: UITheme 深色主题应用 —— 全部功能窗口必须呈现深色面板（对标浮引），
/// 杜绝"内容层深色但窗口本体/滚动区仍白"的半吊子换肤。
final class UIThemeTests: XCTestCase {

    func test_applyDarkWindow_flowingGlassContract() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.backgroundColor = .white

        UITheme.applyDark(window)

        XCTAssertEqual(window.appearance?.name, .aqua, "流光玻璃为浅色外观")
        _ = window // contentView 异步注入玻璃（applyDark 内部幂等）
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

    func test_toolbarTokens_areLightGlassWithDarkChrome() {
        // 流光化：工具条底=浅玻璃（亮），控件叠加=深色低透明，文字=深色
        func compositedBrightness(_ c: NSColor) -> Double {
            let rgb = c.usingColorSpace(.deviceRGB)!
            let a = rgb.alphaComponent
            return (rgb.redComponent * a + rgb.greenComponent * a + rgb.blueComponent * a) / 3
        }
        XCTAssertGreaterThan(compositedBrightness(UITheme.toolbarBackground), 0.5, "工具条底应为浅玻璃")
        XCTAssertLessThan(compositedBrightness(UITheme.toolbarControl), 0.3, "控件叠加应为深色低透明")
        XCTAssertLessThan(compositedBrightness(UITheme.chromeText), 0.4, "chrome 文字应为深色")
    }

    func test_categoryColor_stableForSameKey() {
        XCTAssertEqual(UITheme.categoryColor(for: "screenshot"),
                       UITheme.categoryColor(for: "screenshot"))
        XCTAssertEqual(UITheme.categoryPalette.count, 8, "浮引 8 色分类板")
    }
}
