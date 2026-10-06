import XCTest

/// TDD: 贴图不透明度策略 - 20-100 夹取、默认 100、alphaValue 换算。
final class PinOpacityPolicyTests: XCTestCase {

    func test_clampsBelowMin() {
        XCTAssertEqual(PinOpacityPolicy.clamped(10), 20)
        XCTAssertEqual(PinOpacityPolicy.clamped(0), 20)
    }

    func test_clampsAboveMax() {
        XCTAssertEqual(PinOpacityPolicy.clamped(150), 100)
    }

    func test_passesThroughInRange() {
        XCTAssertEqual(PinOpacityPolicy.clamped(55), 55)
        XCTAssertEqual(PinOpacityPolicy.clamped(20), 20)
        XCTAssertEqual(PinOpacityPolicy.clamped(100), 100)
    }

    func test_defaultIsFullyOpaque() {
        XCTAssertEqual(PinOpacityPolicy.defaultPercent, 100)
    }

    func test_alphaValueConversion() {
        XCTAssertEqual(PinOpacityPolicy.alphaValue(for: 100), 1.0, accuracy: 0.001)
        XCTAssertEqual(PinOpacityPolicy.alphaValue(for: 20), 0.2, accuracy: 0.001)
        XCTAssertEqual(PinOpacityPolicy.alphaValue(for: 35), 0.35, accuracy: 0.001)
    }

    func test_percentFromAlphaValueClamps() {
        XCTAssertEqual(PinOpacityPolicy.percent(fromAlphaValue: 0.35), 35, accuracy: 0.001)
        XCTAssertEqual(PinOpacityPolicy.percent(fromAlphaValue: 0.05), 20, accuracy: 0.001)
        XCTAssertEqual(PinOpacityPolicy.percent(fromAlphaValue: 1.5), 100, accuracy: 0.001)
    }
}
