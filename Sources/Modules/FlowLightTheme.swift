import AppKit
import QuartzCore

/// 流光主题（对标浮引流光外观）：动态流动的彩色渐变玻璃。
/// 结构：FlowingGlassView = 动画渐变层（底层）+ NSVisualEffectView（withinWindow 玻璃折射，顶层）。
public enum FlowLightPalette {
    /// 流光四色（浮引紫/粉/蓝/淡紫系）。
    public static let colors: [NSColor] = [
        NSColor(srgbRed: 0.79, green: 0.65, blue: 0.96, alpha: 1),   // 紫
        NSColor(srgbRed: 0.96, green: 0.72, blue: 0.82, alpha: 1),   // 粉
        NSColor(srgbRed: 0.66, green: 0.78, blue: 0.96, alpha: 1),   // 蓝
        NSColor(srgbRed: 0.88, green: 0.82, blue: 0.96, alpha: 1),   // 淡紫
    ]
}

public enum FlowLightMotion {
    /// 单程流动时长（秒）：缓慢流动，GPU 负载极低。
    public static let cycleDuration: CFTimeInterval = 12

    /// 尊重系统「减弱动态效果」。
    public static func shouldAnimate(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

/// 流光玻璃视图（NSVisualEffectView 子类）：材质之下是窗口桌面模糊，
/// 渐变以 sublayer 叠在材质之上、内容之下——紫色流光透出且内容清晰。
/// 动画健壮性：脱离窗口层级会丢动画，viewDidMoveToWindow 时重挂。
public final class FlowingGlassView: NSVisualEffectView {

    let gradientLayer = CAGradientLayer()

    public init(reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        super.init(frame: .zero)
        material = .underPageBackground
        blendingMode = .behindWindow   // 材质模糊桌面；渐变 sublayer 叠在材质之上
        state = .active

        wantsLayer = true
        gradientLayer.type = .axial
        gradientLayer.colors = FlowLightPalette.colors.map { $0.cgColor }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(gradientLayer)

        if FlowLightMotion.shouldAnimate(reduceMotion: reduceMotion) {
            startFlowAnimation()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 流光动画：颜色与渐变位置缓慢往返（对比度拉开，流动可感知）。
    func startFlowAnimation() {
        let colors = FlowLightPalette.colors.map { $0.cgColor }
        let shifted = Array(colors.dropFirst()) + [colors[0]]

        let colorAnim = CABasicAnimation(keyPath: "colors")
        colorAnim.fromValue = colors
        colorAnim.toValue = shifted
        colorAnim.duration = FlowLightMotion.cycleDuration
        colorAnim.autoreverses = true
        colorAnim.repeatCount = .infinity

        let locAnim = CABasicAnimation(keyPath: "locations")
        locAnim.fromValue = [0.0, 0.35, 0.7, 1.0]
        locAnim.toValue = [0.35, 0.65, 0.9, 1.0]
        locAnim.duration = FlowLightMotion.cycleDuration
        locAnim.autoreverses = true
        locAnim.repeatCount = .infinity

        gradientLayer.add(colorAnim, forKey: "flowColors")
        gradientLayer.add(locAnim, forKey: "flowLocations")
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, FlowLightMotion.shouldAnimate(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else { return }
        if gradientLayer.animation(forKey: "flowColors") == nil {
            startFlowAnimation()
        }
    }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        CATransaction.commit()
    }
}
