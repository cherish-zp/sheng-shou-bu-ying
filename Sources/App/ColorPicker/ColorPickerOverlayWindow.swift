import AppKit

/// 取色覆盖层窗口：无边框、全屏、置顶（screenSaver 层）、可成为 key 窗口，
/// 承载 ColorPickerOverlayView（压暗 + 鼠标移动 + 单击取色 + ESC）。
final class ColorPickerOverlayWindow: NSWindow {

    var pickerView: ColorPickerOverlayView!

    /// 便捷初始化：在指定屏幕上创建全屏覆盖层。
    convenience init(screen: NSScreen) {
        let frame = screen.frame
        self.init(contentRect: frame, styleMask: [.borderless, .fullSizeContentView],
                  backing: .buffered, defer: false)
        let view = ColorPickerOverlayView(frame: NSRect(origin: .zero, size: frame.size))
        self.pickerView = view
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = view
        self.acceptsMouseMovedEvents = true
        self.setFrame(frame, display: true)
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 取色覆盖层视图：轻微压暗 15%（不做选区）；鼠标移动刷新放大镜、
/// 左键单击取色、ESC 退出。压暗只作用于显示层，取色值读自预捕获位图（未压暗），
/// 因此取色值即真实值。
final class ColorPickerOverlayView: NSView {

    /// 左键单击（取色）。
    var onPick: (() -> Void)?
    /// 鼠标移动（刷新放大镜）。
    var onMouseMoved: (() -> Void)?
    /// ESC（退出取色器）。
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        dirtyRect.fill()
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
    }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else { return }
        onPick?()
    }

    override func mouseDragged(with event: NSEvent) {
        // 按住拖动同样跟随刷新放大镜，保持视觉一致
        onMouseMoved?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == ColorPickerSession.escKeyCode {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }
}
