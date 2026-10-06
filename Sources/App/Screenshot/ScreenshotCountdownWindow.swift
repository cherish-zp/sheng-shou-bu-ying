import AppKit

/// 延时截图倒计时浮窗：选区所在屏的全屏透明无焦点窗口，
/// 中央（或选区中央）显示大号倒计时数字，归零由 Coordinator 移除并抓新鲜帧。
/// 鼠标事件穿透（ignoresMouseEvents），但可成为 key 窗口以接收 ESC（经会话级本地监听取消延时）。
final class ScreenshotCountdownWindow: NSPanel {

    private let badgeView = CountdownBadgeView(frame: .zero)

    /// - Parameters:
    ///   - screen: 选区所在屏（倒计时浮窗铺满该屏）。
    ///   - focusRect: 选区 rect（该屏覆盖层视图坐标），数字块优先取其中心。
    init(screen: NSScreen, focusRect: CGRect?) {
        let fullFrame = screen.frame
        super.init(
            contentRect: fullFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // 高于工具条(+2)/子面板(+3)/预览(+4)，确保倒计时数字不被其他截图 UI 遮挡
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 5)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false

        let content = NSView(frame: NSRect(origin: .zero, size: fullFrame.size))
        content.autoresizingMask = [.width, .height]
        contentView = content
        // 视图本地坐标与覆盖层视图坐标同为屏幕本地左下原点，选区中心直接适用
        badgeView.frame = CountdownBadgeLayout.frame(
            containerSize: fullFrame.size, focusRect: focusRect)
        badgeView.autoresizingMask = []
        content.addSubview(badgeView)
    }

    /// borderless 窗口默认不能成为 key；允许后 ESC 才会路由进会话级本地监听。
    override var canBecomeKey: Bool { true }

    /// 显示并显示首个倒计时数字。
    func showCountdown(seconds: Int) {
        update(number: seconds)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    /// 更新倒计时数字。
    func update(number: Int) {
        badgeView.number = number
        badgeView.needsDisplay = true
    }
}

/// 倒计时数字块：半透明黑圆角底 + 白色大号数字，任意壁纸上均可读。
final class CountdownBadgeView: NSView {

    var number: Int = 0

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 28, yRadius: 28)
        NSColor.black.withAlphaComponent(0.55).setFill()
        path.fill()

        let font = NSFont.systemFont(ofSize: 88, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: "\(number)", attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(x: bounds.midX - size.width / 2,
                             y: bounds.midY - size.height / 2))
    }
}
