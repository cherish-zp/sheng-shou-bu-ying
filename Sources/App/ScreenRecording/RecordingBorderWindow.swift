import AppKit

/// 录屏区域红色边框窗口：不接收鼠标事件、不抢焦点，纯视觉提示。
/// 参考截图长截图边框（showScrollBorder）模式自建，层级 screenSaver+3。
final class RecordingBorderWindow: NSPanel {

    init(globalRect: CGRect) {
        super.init(contentRect: globalRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        let content = NSView(frame: NSRect(origin: .zero, size: globalRect.size))
        content.wantsLayer = true
        content.layer?.borderWidth = 3
        content.layer?.borderColor = NSColor.systemRed.cgColor
        content.layer?.cornerRadius = 2
        contentView = content
        orderFrontRegardless()
    }
}
