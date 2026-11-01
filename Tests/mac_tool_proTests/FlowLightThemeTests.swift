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

    func test_flowingGlass_backingLayerIsGradient() {
        // backing layer 直接就是渐变层：时序无关、必然渲染
        let glass = FlowingGlassView()
        XCTAssertFalse(glass is NSVisualEffectView, "不得基于特效视图（会干扰动画）")
        XCTAssertTrue(glass.layer === glass.gradientLayer, "backing layer 必须就是 CAGradientLayer")
        XCTAssertEqual(glass.gradientLayer.type, .axial)
    }

    /// 复刻 app 精确结构：NSWindow + contentView + applyDark + scroll，逐层找白屏元凶。
    func test_appStructure_rendersGradient() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .aqua)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        window.contentView = content
        UITheme.applyDark(window)   // 玻璃注入 content

        let scroll = NSScrollView(frame: content.bounds)
        scroll.drawsBackground = false
        let table = NSTableView()
        table.backgroundColor = .clear
        scroll.documentView = table
        content.addSubview(scroll)
        content.layoutSubtreeIfNeeded()

        let bmp = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bmp)

        var saturated = 0
        for (x, y) in [(50, 50), (150, 50), (50, 150), (150, 150)] {
            guard let c = bmp.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let comps = [c.redComponent, c.greenComponent, c.blueComponent]
            if (comps.max() ?? 0) - (comps.min() ?? 0) > 0.1 { saturated += 1 }
        }
        XCTAssertGreaterThanOrEqual(saturated, 2, "app 同构必须渲染渐变（\(saturated)/4 饱和）")
    }

    func test_flowingGlass_rendersSaturatedPixels() throws {
        // 决定性渲染测试：玻璃视图必须真的画出高饱和渐变（此前静默白屏的回归网）
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 120))
        let glass = FlowingGlassView()
        glass.frame = container.bounds
        container.addSubview(glass)
        container.layoutSubtreeIfNeeded()

        let bmp = try XCTUnwrap(container.bitmapImageRepForCachingDisplay(in: container.bounds))
        container.cacheDisplay(in: container.bounds, to: bmp)

        // 采样四角+中心：必须存在高饱和像素（纯白/纯灰 = 渲染失败）
        var saturated = 0
        var samples = 0
        for (x, y) in [(10, 10), (110, 10), (10, 110), (110, 110), (60, 60)] {
            guard let c = bmp.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            samples += 1
            let comps = [c.redComponent, c.greenComponent, c.blueComponent]
            if (comps.max() ?? 0) - (comps.min() ?? 0) > 0.1 { saturated += 1 }
        }
        XCTAssertGreaterThanOrEqual(saturated, 3, "流光玻璃必须渲染出高饱和渐变像素（\(saturated)/\(samples)）")
    }

    func test_palette_saturated_flowPerceptible() {
        // 饱和度（max-min 分量）> 0.25：颜色间流动才可感知
        for color in FlowLightPalette.colors {
            let rgb = color.usingColorSpace(.deviceRGB)!
            let comps = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
            let saturation = (comps.max() ?? 0) - (comps.min() ?? 0)
            XCTAssertGreaterThan(saturation, 0.25, "流光色饱和度不足：\(color)")
        }
        // 色相分布：四色两两不同（首尾循环亦不同）
        for (i, c) in FlowLightPalette.colors.enumerated() {
            let next = FlowLightPalette.colors[(i + 1) % FlowLightPalette.colors.count]
            XCTAssertNotEqual(c, next)
        }
    }

    func test_applyDark_titleBarReadable() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.backgroundColor = .clear
        UITheme.applyDark(window)
        XCTAssertEqual(window.backgroundColor, UITheme.panelBackground,
                       "标题栏底色必须为浅色可读（不能透明）")
        XCTAssertTrue(window.titlebarAppearsTransparent, "标题栏透明化与玻璃统一")
    }
}
