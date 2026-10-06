import AppKit

/// 贴图右键菜单：复制图片 + 不透明度（内嵌 slider，20%-100% 实时生效）
/// + 恢复不透明 + 鼠标穿透 + 关闭贴图。
/// 复制动作把原始全分辨率 CGImage 经注入的 `Pasteboard` 写入剪贴板；
/// 视图不直接触碰 NSPasteboard.general，动作走抽象注入，便于测试。
/// 不透明度与穿透经闭包回到 PinWindow 本体（菜单控制器不持有窗口强引用）。
final class PinContextMenu: NSObject {

    private let pasteboard: Pasteboard
    private let imageProvider: () -> CGImage?
    private let pointSizeProvider: () -> NSSize
    private let closeHandler: () -> Void
    /// 当前不透明度百分比（slider 初始值），20-100。
    private let opacityProvider: () -> Double
    /// 应用不透明度（拖动 slider 实时回调，松开即最终值生效）。
    private let opacityApplier: (Double) -> Void
    /// 设置/取消鼠标穿透。
    private let penetrationToggler: (Bool) -> Void
    /// 当前是否处于穿透态（穿透中右键不可达，此分支仅作防御展示）。
    private let penetrationStateProvider: () -> Bool

    /// pointSizeProvider 提供贴图原始点尺寸（未缩放），复制时携带与工具条一致的 DPI 口径。
    init(pasteboard: Pasteboard,
         imageProvider: @escaping () -> CGImage?,
         pointSizeProvider: @escaping () -> NSSize,
         closeHandler: @escaping () -> Void,
         opacityProvider: @escaping () -> Double = { PinOpacityPolicy.defaultPercent },
         opacityApplier: @escaping (Double) -> Void = { _ in },
         penetrationToggler: @escaping (Bool) -> Void = { _ in },
         penetrationStateProvider: @escaping () -> Bool = { false }) {
        self.pasteboard = pasteboard
        self.imageProvider = imageProvider
        self.pointSizeProvider = pointSizeProvider
        self.closeHandler = closeHandler
        self.opacityProvider = opacityProvider
        self.opacityApplier = opacityApplier
        self.penetrationToggler = penetrationToggler
        self.penetrationStateProvider = penetrationStateProvider
        super.init()
    }

    /// 不透明度菜单内嵌视图尺寸（label 左 + slider 右）。
    private enum OpacityItemSpec {
        static let width: CGFloat = 230
        static let height: CGFloat = 26
        static let labelLeading: CGFloat = 14
        static let labelWidth: CGFloat = 62
        static let sliderLeading: CGFloat = 8
        static let sliderTrailing: CGFloat = 14
    }

    /// 构建右键菜单（菜单项 target 为 self；self 由贴图视图持有，菜单弹出期间存活）。
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let copyItem = NSMenuItem(title: "复制图片", action: #selector(copyImageToClipboard(_:)), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        menu.addItem(.separator())

        menu.addItem(makeOpacityItem())
        let resetItem = NSMenuItem(title: "恢复不透明", action: #selector(resetOpacity(_:)), keyEquivalent: "")
        resetItem.target = self
        resetItem.isEnabled = opacityProvider() != PinOpacityPolicy.maxPercent
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let penetrateItem = NSMenuItem(
            title: penetrationStateProvider() ? "鼠标穿透已开启（按 F6 恢复）" : "开启鼠标穿透（按 F6 恢复）",
            action: #selector(enableMousePenetration(_:)), keyEquivalent: "")
        penetrateItem.target = self
        penetrateItem.isEnabled = !penetrationStateProvider()
        menu.addItem(penetrateItem)

        menu.addItem(.separator())

        let closeItem = NSMenuItem(title: "关闭贴图", action: #selector(closePinFromMenu(_:)), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        return menu
    }

    /// 「不透明度」菜单项：内嵌横向 slider（20-100），拖动实时调整贴图 alphaValue。
    private func makeOpacityItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0,
                                             width: OpacityItemSpec.width,
                                             height: OpacityItemSpec.height))
        let label = NSTextField(labelWithString: "不透明度")
        label.font = NSFont.systemFont(ofSize: 13)
        label.frame = NSRect(x: OpacityItemSpec.labelLeading, y: 5,
                             width: OpacityItemSpec.labelWidth, height: 17)
        container.addSubview(label)

        let slider = NSSlider(value: opacityProvider(),
                              minValue: PinOpacityPolicy.minPercent,
                              maxValue: PinOpacityPolicy.maxPercent,
                              target: self,
                              action: #selector(opacitySliderChanged(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(
            x: OpacityItemSpec.labelLeading + OpacityItemSpec.labelWidth + OpacityItemSpec.sliderLeading,
            y: 3,
            width: OpacityItemSpec.width - OpacityItemSpec.labelLeading - OpacityItemSpec.labelWidth
                - OpacityItemSpec.sliderLeading - OpacityItemSpec.sliderTrailing,
            height: 20)
        container.addSubview(slider)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    /// 在视图坐标 point 处弹出菜单。
    func popUp(at point: NSPoint, in view: NSView) {
        makeMenu().popUp(positioning: nil, at: point, in: view)
    }

    // MARK: - 动作

    @objc private func copyImageToClipboard(_ sender: NSMenuItem) {
        guard let image = imageProvider() else { return }
        let pointSize = pointSizeProvider()
        pasteboard.copyImage(image, pointSize: pointSize)
        DiagLog.write("PinContextMenu: 已复制图片 \(image.width)x\(image.height)（pointSize \(pointSize.width)x\(pointSize.height)）到剪贴板")
    }

    /// slider 拖动（continuous）：每次变化实时应用到贴图。
    @objc private func opacitySliderChanged(_ sender: NSSlider) {
        opacityApplier(PinOpacityPolicy.clamped(sender.doubleValue))
    }

    /// 恢复不透明（100%）。
    @objc private func resetOpacity(_ sender: NSMenuItem) {
        opacityApplier(PinOpacityPolicy.defaultPercent)
        DiagLog.write("PinContextMenu: opacity reset to 100%")
    }

    /// 开启鼠标穿透：贴图对鼠标完全透明，F6 全局恢复。
    @objc private func enableMousePenetration(_ sender: NSMenuItem) {
        penetrationToggler(true)
        DiagLog.write("PinContextMenu: mouse penetration enabled (F6 to restore)")
    }

    @objc private func closePinFromMenu(_ sender: NSMenuItem) {
        closeHandler()
    }
}
