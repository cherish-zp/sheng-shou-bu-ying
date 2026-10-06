import AppKit
import Carbon.HIToolbox

/// 贴图窗口：将截图钉在桌面上，始终置顶、可拖动、可关闭。
/// 直接使用原始 CGImage 绘制，避免 NSImage 转换导致色差/模糊。
/// 窗口四周留 shadowMargin 透明边距，图片视图用图层阴影投出柔和投影——
/// 白底贴图浮在白色背景上时，系统默认阴影太弱、卡片轮廓消失，
/// 边缘发丝线会被误读为内容里的杂线。
/// 呼吸灯样式可配置（横条/圆点），横条的高度/距顶部间距/颜色均可在设置中调整，
/// 设置变更立即生效。
/// 贴图增强（v2）：不透明度可调（20%-100%，会话内有效不持久化）、
/// 鼠标穿透（ignoresMouseEvents，穿透中的贴图以虚线边框作视觉提示，
/// 按 F6 全局恢复全部穿透贴图）。
final class PinWindow: NSWindow {

    /// 贴图关闭时回调（用于协调器从列表中移除、释放图片）。
    var onClose: (() -> Void)?

    private var styleObserver: NSObjectProtocol?

    init(cgImage: CGImage, displaySize: NSSize, at point: CGPoint, cornerRadius: CGFloat = 0) {
        let margin = PinImageView.shadowMargin
        let frame = NSRect(x: point.x - margin, y: point.y - margin,
                           width: displaySize.width + margin * 2,
                           height: displaySize.height + margin * 2)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovable = true
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = PinWindowContentView()
        container.wantsLayer = true
        let imageView = PinImageView(frame: NSRect(origin: .zero, size: displaySize))
        imageView.cgImage = cgImage
        imageView.baseCornerRadius = cornerRadius
        imageView.setOriginalSize(displaySize)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        container.imageView = imageView
        NSLayoutConstraint.activate([
            // 四边距约束：图片视图随窗口缩放（滚轮缩放窗口 frame 时同步），
            // 边距恒定；若用固定宽高约束，缩放时图片锚死左上角、内容会到处滑动
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: margin),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -margin),
        ])
        contentView = container

        // 右键菜单：复制图片 + 不透明度 + 鼠标穿透 + 关闭贴图
        // （关闭走右键，取代原左上角悬停 X 按钮；不透明度/穿透经闭包回到窗口本体）
        imageView.addContextMenu(PinContextMenu(
            pasteboard: SystemPasteboard(),
            imageProvider: { [weak imageView] in imageView?.cgImage },
            pointSizeProvider: { [weak imageView] in imageView?.originalSize ?? .zero },
            closeHandler: { [weak self] in self?.closePin() },
            opacityProvider: { [weak self] in
                PinOpacityPolicy.percent(fromAlphaValue: Double(self?.alphaValue ?? 1))
            },
            opacityApplier: { [weak self] percent in self?.setOpacity(percent: percent) },
            penetrationToggler: { [weak self] on in self?.setMousePenetrating(on) },
            penetrationStateProvider: { [weak self] in self?.isMousePenetrating ?? false }
        ))

        // 呼吸灯样式与外观：读取设置（默认顶部横条，高 4pt、距顶 2pt、绿色）
        imageView.applyIndicatorSettings(PinSettingsStore.defaultStore().load())

        // 设置变更立即生效于已打开的贴图
        styleObserver = NotificationCenter.default.addObserver(
            forName: .pinIndicatorStyleDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self, let imageView = self.contentView as? PinWindowContentView else { return }
            imageView.imageView?.applyIndicatorSettings(PinSettingsStore.defaultStore().load())
        }

        DiagLog.write("PinWindow: pts=\(displaySize) pixels=\(cgImage.width)x\(cgImage.height) backingScale=\(self.backingScaleFactor)")
    }

    deinit {
        if let observer = styleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        PenetratedPinRegistry.shared.remove(self)
    }

    /// 关闭贴图并通知协调器释放资源。
    @objc func closePin() {
        orderOut(nil)
        if isMousePenetrating {
            PenetratedPinRegistry.shared.remove(self)
            isMousePenetrating = false
        }
        onClose?()
    }

    // MARK: - 贴图增强：不透明度与鼠标穿透

    /// 当前是否处于鼠标穿透态（穿透中的贴图对鼠标完全透明，仅 F6 可恢复交互）。
    private(set) var isMousePenetrating = false

    /// 设置不透明度（20-100，经 PinOpacityPolicy 夹取），拖动 slider 实时生效。
    /// 不持久化：每张贴图独立、会话内有效。
    func setOpacity(percent: Double) {
        alphaValue = PinOpacityPolicy.alphaValue(for: percent)
        DiagLog.write("PinWindow: opacity -> \(PinOpacityPolicy.clamped(percent))%")
    }

    /// 设置鼠标穿透：开启后贴图对鼠标完全透明（可点击其后方内容），
    /// 登记到 PenetratedPinRegistry 并惰性注册 F6 逃生热键；关闭即恢复交互。
    /// 穿透中的视觉提示：图片边框变为橙色虚线（不用透明度变化，避免与用户手动
    /// 调节的不透明度相互覆盖）。
    func setMousePenetrating(_ on: Bool) {
        guard on != isMousePenetrating else { return }
        isMousePenetrating = on
        ignoresMouseEvents = on
        (contentView as? PinWindowContentView)?.imageView?.isPenetrating = on
        if on {
            PenetratedPinRegistry.shared.add(self)
            PinPenetrationEscape.shared.ensureRegistered()
        } else {
            PenetratedPinRegistry.shared.remove(self)
        }
        DiagLog.write("PinWindow: mouse penetration -> \(on)")
    }

    /// 从穿透态恢复交互（F6 逃生通道逐张调用）。
    func restoreFromPenetration() {
        setMousePenetrating(false)
    }
}

/// 贴图穿透逃生通道：F6 全局热键恢复所有处于穿透态的贴图。
/// 语义：穿透中的贴图 ignoresMouseEvents = true，右键菜单已不可达，
/// F6 是唯一交互出口——按下后全部恢复并 Toast「已恢复 N 张贴图交互」。
/// F6 为全局消费（系统默认把 F6 给「听写」等，本 App 抢占，自用可接受）。
/// 实现说明：测试 target 只编译贴图两件套（PinWindow/PinContextMenu），
/// 为保证其可独立编译，此处内联 Carbon RegisterEventHotKey/InstallEventHandler
/// 而不引用 Screenshot 目录下的 CarbonHotkeyRegistrar；热键 id 取冷门值，
/// 与 HotkeyManager 的自增 id 空间隔离，互相不干扰。
final class PinPenetrationEscape {

    static let shared = PinPenetrationEscape()

    /// 本逃生热键的 Carbon id（0xF60006，避开 HotkeyManager 的自增小 id）。
    private static let hotkeyID: UInt32 = 0xF60006

    private var registered = false
    private var handlerInstalled = false

    private init() {}

    /// 首次有贴图进入穿透态时调用：注册 F6 并安装分发 handler（幂等）。
    func ensureRegistered() {
        if !registered {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x6D745F70), id: PinPenetrationEscape.hotkeyID)
            let status = RegisterEventHotKey(Hotkey.f6.keyCode, Hotkey.f6.modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, ref != nil else {
                DiagLog.write("PinPenetrationEscape: RegisterEventHotKey F6 failed status=\(status)")
                return
            }
            registered = true
            DiagLog.write("PinPenetrationEscape: F6 registered (restore penetrated pins)")
        }
        installHandlerIfNeeded()
    }

    /// 安装 Carbon 事件 handler（幂等）。handler 是 C 函数指针，不能捕获上下文，
    /// 经静态类型转发；只处理自己的 hotkey id，其余热键（如 HotkeyManager 的 F1）原样放行。
    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, eventRef, _ in
            guard let eventRef = eventRef else { return noErr }
            var hotKeyID = EventHotKeyID(signature: 0, id: 0)
            let status = GetEventParameter(eventRef,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr, hotKeyID.id == PinPenetrationEscape.hotkeyID else { return noErr }
            DispatchQueue.main.async {
                PinPenetrationEscape.shared.restoreAllPenetrated()
            }
            return noErr
        }
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, nil, nil)
        DiagLog.write("PinPenetrationEscape: InstallEventHandler status=\(installStatus)")
    }

    /// 恢复全部穿透态贴图并提示数量。
    private func restoreAllPenetrated() {
        let pins = PenetratedPinRegistry.shared.removeAllEntries()
        for pin in pins {
            (pin as? PinWindow)?.restoreFromPenetration()
        }
        guard !pins.isEmpty else { return }
        TransientHudToast.show(text: "已恢复 \(pins.count) 张贴图交互")
        DiagLog.write("PinPenetrationEscape: restored \(pins.count) penetrated pin(s)")
    }
}

/// 通用轻量 HUD 提示：毛玻璃面板、屏幕顶部居中、淡入淡出自动消失。
/// 定义于贴图文件供「F6 恢复贴图」与取色器复制提示共用（层级取
/// screenSaver+2，保证盖在全屏取色覆盖层之上；CopyToastPresenter 的
/// .statusBar 层级会被取色覆盖层遮挡）。
final class TransientHudToast {

    private static var currentPanel: NSPanel?
    private static var hideWorkItem: DispatchWorkItem?
    private static var generation = 0

    private enum Spec {
        static let fadeInDuration: TimeInterval = 0.18
        static let visibleDuration: TimeInterval = 1.6
        static let fadeOutDuration: TimeInterval = 0.28
        static let cornerRadius: CGFloat = 14
        static let topGap: CGFloat = 8
        static let iconSize: CGFloat = 18
        static let level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
    }

    /// 展示一条提示（连续调用时旧提示的定时隐藏作废）。
    static func show(text: String) {
        DispatchQueue.main.async {
            present(text: text)
        }
    }

    private static func present(text: String) {
        generation += 1
        let currentGeneration = generation
        hideWorkItem?.cancel()
        hideWorkItem = nil

        let panel = makePanel(text: text)
        currentPanel = panel
        position(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Spec.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        })

        let item = DispatchWorkItem {
            guard generation == currentGeneration else { return }
            dismiss(panel)
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Spec.fadeInDuration + Spec.visibleDuration, execute: item)
    }

    private static func makePanel(text: String) -> NSPanel {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let panelWidth = min(520, 14 + Spec.iconSize + 7 + textWidth + 14)
        let panelHeight: CGFloat = 44

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = Spec.level
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.hidesOnDeactivate = false

        let visual = NSVisualEffectView()
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = Spec.cornerRadius
        visual.layer?.masksToBounds = true
        visual.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = visual

        let symbol = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: text) ?? NSImage()
        let icon = NSImageView(image: symbol)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(icon)

        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: visual.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: visual.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Spec.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Spec.iconSize),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: visual.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: visual.trailingAnchor, constant: -14),
        ])
        return panel
    }

    /// 定位到主屏可见区顶部居中。
    private static func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.maxY - panel.frame.height - Spec.topGap
        )
        panel.setFrameOrigin(origin)
    }

    private static func dismiss(_ panel: NSPanel?) {
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Spec.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            guard panel.alphaValue == 0 else { return }
            panel.orderOut(nil)
            if currentPanel === panel { currentPanel = nil }
        })
    }
}

/// 贴图窗口内容容器：窗口比图片大一圈（阴影边距），
/// 边距区域不响应鼠标（hitTest 返回 nil，不挡贴图背后的点击目标）。
final class PinWindowContentView: NSView {

    weak var imageView: PinImageView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let imageView = imageView else { return super.hitTest(point) }
        let local = convert(point, from: nil)
        return imageView.frame.contains(local) ? imageView : nil
    }
}

/// 贴图视图：直接用 CGContext.draw 绘制原始 CGImage，与覆盖层渲染方式一致。
/// 处理拖拽移动 + 双击关闭。管理呼吸灯样式（横条/圆点）与关闭按钮。
final class PinImageView: NSView {

    /// 窗口四周的透明阴影边距（点）。
    static let shadowMargin: CGFloat = 20

    var cgImage: CGImage?
    /// 贴图基础圆角半径（点，未缩放时口径），用于呼吸灯贴合图片圆角；0 表示直角。
    var baseCornerRadius: CGFloat = 0
    /// 是否处于鼠标穿透态：true 时边框改为橙色虚线作视觉提示
    /// （不透明度提示会与用户手动调节的透明度相互覆盖，故用边框形态区分）。
    var isPenetrating = false {
        didSet { needsDisplay = true }
    }
    private var closeButton: PinCloseButton?
    private var indicatorBar: PinIndicatorBar?
    /// 贴图原始点尺寸（创建时传入的 displaySize，未随滚轮缩放变化），
    /// 供右键复制携带与工具条一致的点尺寸口径。
    private(set) var originalSize: CGSize = .zero
    private var currentScale: CGFloat = 1.0

    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var lastClickTime: Date = .distantPast
    private let doubleClickInterval: TimeInterval = 0.3
    private var contextMenuController: PinContextMenu?

    /// 挂接右键菜单控制器（窗口创建时注入，复制动作经 Pasteboard 抽象执行）。
    func addContextMenu(_ controller: PinContextMenu) {
        contextMenuController = controller
    }

    /// 设置原始尺寸（初始化时调用），用于缩放基准。
    func setOriginalSize(_ size: CGSize) {
        originalSize = size
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { false }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // 图层阴影投到窗口的透明边距里：跟随图片圆角轮廓，
        // 让白底贴图在同色背景上有清晰的"悬浮卡片"边界
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.30
        layer?.shadowRadius = 14
        layer?.shadowOffset = NSSize(width: 0, height: -4)
        layer?.masksToBounds = false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let cg = cgImage else { return }
        ctx.draw(cg, in: bounds)
        // 发丝描边：贴图圆角烘焙为透明像素，白底贴图放在白色背景上弧度不可见；
        // 显示层描 1pt 边框（跟随贴图圆角、随缩放同步）让弧度在任何背景上可见。
        // 仅显示层，不修改图片像素（复制/保存内容不变）。
        let radius = CornerRounding.clampedRadius(baseCornerRadius * currentScale, for: bounds.size)
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        if isPenetrating {
            // 鼠标穿透视觉提示：橙色虚线（宽 2pt、dash 6/4），穿透中的贴图一眼可辨
            ctx.setStrokeColor(NSColor.systemOrange.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
        } else {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.20).cgColor)
            ctx.setLineWidth(1)
        }
        if radius > 0 {
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        } else {
            ctx.addRect(rect)
        }
        ctx.strokePath()
        if isPenetrating {
            ctx.setLineDash(phase: 0, lengths: [])
        }
    }

    /// 按设置应用呼吸灯：样式（横条/圆点）+ 横条外观（高度/距顶部间距/颜色）。
    /// topBar 模式不再创建悬停 X 关闭按钮（关闭已改由右键菜单承担）；
    /// cornerDot 模式保留左上角圆点（闪烁指示，点击仍可关闭）。
    /// 可重复调用（初始化与设置变更通知共用）。
    func applyIndicatorSettings(_ settings: PinSettingsState) {
        if settings.indicatorStyle == .cornerDot {
            if closeButton == nil {
                let button = PinCloseButton()
                addCloseButton(button)
            }
            closeButton?.setMode(.cornerDot)
            updateCloseButtonFrame()
        } else {
            closeButton?.removeFromSuperview()
            closeButton = nil
        }
        if settings.indicatorStyle == .topBar {
            if indicatorBar == nil {
                let bar = PinIndicatorBar()
                addSubview(bar)
                indicatorBar = bar
            }
            indicatorBar?.barHeight = settings.indicatorHeight
            indicatorBar?.topInset = settings.indicatorTopInset
            indicatorBar?.color = PinIndicatorColor.color(fromHex: settings.indicatorColorHex)
                ?? PinIndicatorColor.color(fromHex: PinIndicatorColor.defaultHex)!
            indicatorBar?.silhouetteRadius = baseCornerRadius * currentScale
            updateIndicatorBarFrame()
        } else {
            indicatorBar?.removeFromSuperview()
            indicatorBar = nil
        }
    }

    /// 添加关闭按钮到左上角。
    func addCloseButton(_ button: PinCloseButton) {
        closeButton = button
        button.autoresizingMask = []
        addSubview(button)
        updateCloseButtonFrame()
    }

    /// 根据当前缩放比例与模式更新关闭按钮的位置和大小。
    /// 圆点模式用常规尺寸系（22pt），横条模式用减半的浮现按钮尺寸系。
    func updateCloseButtonFrame() {
        guard let btn = closeButton else { return }
        switch btn.mode {
        case .cornerDot:
            btn.frame = PinScaler.scaledButtonFrame(viewBounds: bounds, scaleFactor: currentScale)
        case .topBar:
            btn.frame = PinScaler.scaledRevealButtonFrame(viewBounds: bounds, scaleFactor: currentScale)
        }
        btn.needsDisplay = true
    }

    /// 顶部横条 frame：高度与距顶间距来自设置（视图原点左下，顶部 = maxY）。
    private func updateIndicatorBarFrame() {
        guard let bar = indicatorBar else { return }
        bar.frame = NSRect(x: 0,
                           y: bounds.height - bar.topInset - bar.barHeight,
                           width: bounds.width,
                           height: bar.barHeight)
    }

    override func mouseDown(with event: NSEvent) {
        // 点击关闭按钮时不触发拖拽
        let point = convert(event.locationInWindow, from: nil)
        if let btn = closeButton, btn.frame.contains(point) { return }
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let newOrigin = SelectionRect.dragOrigin(
            initialOrigin: dragStartOrigin,
            initialMouse: dragStartMouse,
            currentMouse: current
        )
        window?.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let btn = closeButton, btn.frame.contains(point) { return }
        let now = Date()
        if now.timeIntervalSince(lastClickTime) < doubleClickInterval {
            (window as? PinWindow)?.closePin()
        }
        lastClickTime = now
    }

    /// 右键弹出贴图菜单；NSView 的 rightMouseDown 独立于左键 mouseDown/mouseUp 事件流，
    /// 不影响拖拽与双击关闭。
    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        contextMenuController?.popUp(at: point, in: self)
    }

    /// 滚轮缩放：上滚放大、下滚缩小，等比例缩放，光标锚定（指哪、哪不动）。
    override func scrollWheel(with event: NSEvent) {
        let delta = event.deltaY
        guard abs(delta) > 0.01 else { return }
        let scaleDelta = 1.0 + delta * 0.1
        currentScale = PinScaler.clampedScaleFactor(currentScale * scaleDelta)
        guard let win = window, originalSize.width > 0 else { return }
        let newSize = PinScaler.scaledSize(original: originalSize, scaleFactor: currentScale)
        // 窗口 frame 含四周阴影边距，缩放目标尺寸需补回边距；
        // 锚点 = 当前光标位置（屏幕坐标），保证光标下的画面缩放时不动
        let margin = PinImageView.shadowMargin
        let windowSize = NSSize(width: newSize.width + margin * 2,
                                height: newSize.height + margin * 2)
        let mouse = NSEvent.mouseLocation
        let anchor = window!.frame.contains(mouse) ? mouse
            : CGPoint(x: window!.frame.midX, y: window!.frame.midY)
        let newFrame = PinScaler.scaledFrame(originalFrame: win.frame, newSize: windowSize,
                                             anchorInFrame: anchor)
        win.setFrame(newFrame, display: true)
        updateCloseButtonFrame()
        indicatorBar?.silhouetteRadius = baseCornerRadius * currentScale
    }
}

/// 顶部呼吸横条：胶囊形浮动条，距贴图顶部间距与高度、颜色均来自设置。
/// 用 Core Animation 透明度渐变实现渐亮渐暗，无需定时器重绘。
/// 两端除胶囊圆角外再经「贴图轮廓（圆角矩形）」裁剪，保证不越过贴图圆角外的透明区域。
final class PinIndicatorBar: NSView {

    /// 横条高度（点），来自设置。
    var barHeight: CGFloat = PinIndicatorAppearance.defaultHeight {
        didSet { needsDisplay = true }
    }
    /// 距贴图顶部间距（点），同时用于轮廓裁剪定位。
    var topInset: CGFloat = PinIndicatorAppearance.defaultTopInset
    /// 横条颜色，来自设置色板。
    var color: NSColor = PinIndicatorColor.color(fromHex: PinIndicatorColor.defaultHex)! {
        didSet { needsDisplay = true }
    }
    /// 贴图当前圆角半径（点，= baseRadius × currentScale），0 表示直角贴图。
    var silhouetteRadius: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .minYMargin]
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startBreathing()
        } else {
            layer?.removeAnimation(forKey: "breathing")
        }
    }

    /// 呼吸：最低 45% 亮度（永不淡成幻影线）→ 100%，缓入缓出。
    private func startBreathing() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = PinIndicatorAppearance.breathMinOpacity
        anim.toValue = PinIndicatorAppearance.breathMaxOpacity
        anim.duration = 1.2
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(anim, forKey: "breathing")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // 贴图轮廓裁剪：圆角矩形顶边在横条顶边上方 topInset 处（横条自身坐标系 y 向下）
        if silhouetteRadius > 0 {
            let silhouette = NSRect(x: 0, y: -topInset, width: bounds.width,
                                    height: bounds.height + topInset + silhouetteRadius + 8)
            ctx.addPath(CGPath(roundedRect: silhouette, cornerWidth: silhouetteRadius,
                               cornerHeight: silhouetteRadius, transform: nil))
            ctx.clip()
        }
        // 灯体光晕：同色柔光让横条读作"发光的灯"而非一条淡线
        ctx.setShadow(offset: .zero, blur: 3, color: color.withAlphaComponent(0.55).cgColor)
        // 胶囊形状（圆角 = 高度一半）
        let capsule = CGPath(roundedRect: bounds, cornerWidth: bounds.height / 2,
                             cornerHeight: bounds.height / 2, transform: nil)
        ctx.addPath(capsule)
        ctx.clip()
        ctx.setFillColor(color.cgColor)
        ctx.fill(bounds)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

/// 贴图关闭按钮：左上角圆形按钮，点击关闭。
/// 圆点模式：亮绿色闪烁，悬停变红并显示X；横条模式：悬停贴图时淡入红色X。
final class PinCloseButton: NSView {

    private var state = PinCloseButtonState()
    private let buttonSize: CGFloat = 22
    private var blinkTimer: Timer?

    override var isFlipped: Bool { true }

    /// 当前指示样式模式（圆点/横条），供按模式选按钮尺寸系。
    var mode: PinCloseButtonState.Mode { state.mode }

    /// 切换指示样式模式（横条/圆点），重置可见性与闪烁。
    func setMode(_ mode: PinCloseButtonState.Mode) {
        state.setMode(mode)
        updateBlinking()
        applyVisibility()
    }

    /// 横条模式：由贴图悬停状态驱动浮现/隐藏；圆点模式下忽略。
    func setImageHovered(_ hovered: Bool) {
        guard state.mode == .topBar else { return }
        hovered ? state.onImageHoverEnter() : state.onImageHoverExit()
        applyVisibility()
    }

    private func updateBlinking() {
        if state.mode == .cornerDot && window != nil {
            startBlinking()
        } else {
            stopBlinking()
        }
    }

    /// 可见性淡入淡出（横条模式浮现/隐藏，0.15s）。
    private func applyVisibility() {
        let target: CGFloat = state.isVisible ? 1 : 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = target
        }
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBlinking()
    }

    private func startBlinking() {
        stopBlinking()
        blinkTimer = Timer.scheduledTimer(
            withTimeInterval: PinCloseButtonState.blinkInterval, repeats: true
        ) { [weak self] _ in
            guard let self = self else { return }
            self.state.onBlinkTick()
            self.needsDisplay = true
        }
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    // 圆点为纯闪烁指示灯：不悬停变色、不显示 X、点击不关闭（关闭统一走右键菜单）

    override func draw(_ dirtyRect: NSRect) {
        guard state.isVisible else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        // 圆形背景
        let bgColor: NSColor = state.color == .red
            ? NSColor(calibratedRed: 1.0, green: 0.23, blue: 0.19, alpha: 0.95)
            : NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.31, alpha: 0.90)
        ctx.setFillColor(bgColor.cgColor)
        ctx.fillEllipse(in: rect)

        // 悬停时显示白色X（随按钮尺寸等比：22pt 时 r≈4、线宽≈2，与原视觉一致）
        if state.showsX {
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let r = bounds.width * 0.18
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(Swift.max(1.5, bounds.width * 0.09))
            ctx.setLineCap(.round)
            ctx.move(to: NSPoint(x: center.x - r, y: center.y - r))
            ctx.addLine(to: NSPoint(x: center.x + r, y: center.y + r))
            ctx.move(to: NSPoint(x: center.x + r, y: center.y - r))
            ctx.addLine(to: NSPoint(x: center.x - r, y: center.y + r))
            ctx.strokePath()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}
