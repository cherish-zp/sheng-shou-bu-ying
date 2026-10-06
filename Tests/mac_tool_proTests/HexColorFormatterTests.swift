import XCTest
import CoreGraphics

/// TDD: 颜色格式化 - rgba/CGColor → #RRGGBB 与 rgb(r, g, b)。
/// 边界：alpha 忽略、分量四舍五入并夹取 0-255、灰度 CGColor 展开。
final class HexColorFormatterTests: XCTestCase {

    // MARK: - rgba 分量

    func test_hexString_primaryRed() {
        XCTAssertEqual(HexColorFormatter.hexString(red: 1, green: 0, blue: 0), "#FF0000")
    }

    func test_hexString_roundsHalfUp() {
        // 0.5 * 255 = 127.5 → 128 = 0x80
        XCTAssertEqual(HexColorFormatter.hexString(red: 0.5, green: 0.5, blue: 0.5), "#808080")
    }

    func test_hexString_clampsOutOfRangeComponents() {
        XCTAssertEqual(HexColorFormatter.hexString(red: 1.2, green: -0.1, blue: 0), "#FF0000")
    }

    func test_hexString_mixedValues() {
        XCTAssertEqual(HexColorFormatter.hexString(red: 0, green: 1, blue: 0.5), "#00FF80")
    }

    func test_rgbString_matchesHexRounding() {
        XCTAssertEqual(HexColorFormatter.rgbString(red: 1, green: 0.2, blue: 0), "rgb(255, 51, 0)")
    }

    // MARK: - CGColor

    func test_cgColor_ignoresAlpha() {
        let color = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 0.3)
        XCTAssertEqual(HexColorFormatter.hexString(from: color), "#0000FF")
        XCTAssertEqual(HexColorFormatter.rgbString(from: color), "rgb(0, 0, 255)")
    }

    func test_cgColor_grayExpandsToEqualComponents() {
        // 0.25 * 255 = 63.75 → 64 = 0x40
        let gray = CGColor(gray: 0.25, alpha: 1)
        XCTAssertEqual(HexColorFormatter.hexString(from: gray), "#404040")
    }

    func test_cgColor_rgbString_matchesHexString() {
        let color = CGColor(srgbRed: 0.5, green: 0.25, blue: 0, alpha: 1)
        XCTAssertEqual(HexColorFormatter.rgbString(from: color), "rgb(128, 64, 0)")
    }
}
