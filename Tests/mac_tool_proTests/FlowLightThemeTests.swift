import XCTest
import AppKit

/// TDD: 流光主题 —— 调色板/动效策略/令牌翻转（浅磨砂玻璃 + 深色文字，对标浮引流光）。
final class FlowLightThemeTests: XCTestCase {

    func test_palette_fourPastelColors() {
        XCTAssertEqual(FlowLightPalette.colors.count, 4)
        for color in FlowLightPalette.colors {
            let rgb = color.usingColorSpace(.deviceRGB)!
            let brightness = (rgb.redComponent + rgb.greenComponent + rgb.blueComponent) / 3
            XCTAssertGreaterThan(brightness, 0.5, "流光色应为柔和亮色")
            XCTAssertLessThan(brightness, 0.95, "不应接近纯白")
        }
    }

    func test_motionPolicy_respectsReducedMotion() {
        XCTAssertFalse(FlowLightMotion.shouldAnimate(reduceMotion: true),
                       "系统开启减弱动态效果时必须静止")
        XCTAssertTrue(FlowLightMotion.shouldAnimate(reduceMotion: false))
    }

    func test_motionDuration_slow() {
        XCTAssertGreaterThanOrEqual(FlowLightMotion.cycleDuration, 8, "流动须缓慢（≥8s）")
    }

    func test_tokens_flippedToLightGlassDarkText() {
        // 全面流光化后：主文字=深色、卡片=浅玻璃
        let textRGB = UITheme.textPrimary.usingColorSpace(.deviceRGB)!
        let textBrightness = (textRGB.redComponent + textRGB.greenComponent + textRGB.blueComponent) / 3
        XCTAssertLessThan(textBrightness, 0.4, "流光玻璃上主文字应为深色")
        let cardRGB = UITheme.cardBackground.usingColorSpace(.deviceRGB)!
        let cardBrightness = (cardRGB.redComponent + cardRGB.greenComponent + cardRGB.blueComponent) / 3
        XCTAssertGreaterThan(cardBrightness, 0.6, "卡片应为浅玻璃")
    }

    func test_flowingGlassView_createsWithWithinWindowBlending() {
        let glass = FlowingGlassView()
        XCTAssertEqual(glass.blendingMode, NSVisualEffectView.BlendingMode.withinWindow)
        XCTAssertEqual(glass.material, .underPageBackground)
        XCTAssertNotNil(glass.gradientLayer, "渐变层必须存在（流光载体）")
    }
}
