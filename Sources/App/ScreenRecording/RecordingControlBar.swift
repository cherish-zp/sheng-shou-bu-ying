import AppKit

/// 录屏悬浮控制条：深色毛玻璃圆角小条（复刻截图工具条视觉语言），可拖动。
/// 两种形态：
/// - armed（已框选待录）：[⏺ 开始录制] [✕]
/// - recording：[计时标签] [⏸/▶ 切换] [⏹ 停止(红)] [✕ 取消]
/// 层级 screenSaver+3（高于边框），isMovableByWindowBackground 支持拖动。
final class RecordingControlBar: NSPanel {

    var onStart: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    private enum Spec {
        static let cornerRadius: CGFloat = 12
        static let barHeight: CGFloat = 44
        static let buttonSize: CGFloat = 28
        static let padding: CGFloat = 10
    }

    private var durationLabel: NSTextField?
    private var pauseButton: NSButton?
    private var isPausedUI = false
    private(set) var mode: Mode = .armed

    enum Mode {
        case armed
        case recording
    }

    init() {
        let frame = NSRect(x: 0, y: 0, width: 220, height: Spec.barHeight)
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
    }

    // MARK: - 形态切换

    /// 待录形态：开始 / 取消。
    func showArmed(at origin: NSPoint) {
        mode = .armed
        rebuildContent()
        setFrameOrigin(origin)
        orderFrontRegardless()
    }

    /// 录制形态：计时 / 暂停恢复 / 停止 / 取消。
    func showRecording(at origin: NSPoint) {
        mode = .recording
        rebuildContent()
        setFrameOrigin(origin)
        orderFrontRegardless()
    }

    /// 更新计时文案。
    func updateDuration(_ text: String) {
        durationLabel?.stringValue = text
    }

    /// 同步暂停按钮状态（▶/⏸ 切换）。
    func setPaused(_ paused: Bool) {
        isPausedUI = paused
        guard let button = pauseButton else { return }
        let symbolName = paused ? "play.fill" : "pause.fill"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: paused ? "恢复" : "暂停")
        button.contentTintColor = .white
    }

    // MARK: - UI 构建

    private func rebuildContent() {
        let width: CGFloat = mode == .armed ? 150 : 220
        setFrame(NSRect(x: frame.origin.x, y: frame.origin.y, width: width, height: Spec.barHeight),
                 display: false)

        let visual = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = Spec.cornerRadius
        visual.layer?.masksToBounds = true
        visual.autoresizingMask = [.width, .height]
        contentView = visual

        var buttons: [NSView] = []
        if mode == .armed {
            buttons.append(makeButton(symbol: "record.circle", tooltip: "开始录制", tint: .systemRed,
                                      action: #selector(startClicked)))
            buttons.append(makeLabel("待录制"))
            buttons.append(makeButton(symbol: "xmark", tooltip: "取消", tint: .secondaryLabelColor,
                                      action: #selector(cancelClicked)))
        } else {
            durationLabel = makeLabel("00:00")
            buttons.append(durationLabel!)
            buttons.append(makeButton(symbol: "pause.fill", tooltip: "暂停/恢复", tint: .white,
                                      action: #selector(togglePauseClicked)))
            buttons.append(makeButton(symbol: "stop.fill", tooltip: "停止并预览", tint: .systemRed,
                                      action: #selector(stopClicked)))
            buttons.append(makeButton(symbol: "xmark", tooltip: "取消录制", tint: .secondaryLabelColor,
                                      action: #selector(cancelClicked)))
        }
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: visual.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: visual.centerYAnchor),
        ])
    }

    private func makeButton(symbol: String, tooltip: String, tint: NSColor, action: Selector) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: Spec.buttonSize, height: Spec.buttonSize))
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.image?.isTemplate = true
        button.contentTintColor = tint
        button.isBordered = false
        button.title = ""
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.target = self
        button.action = action
        return button
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        return label
    }

    // MARK: - 动作

    @objc private func startClicked() { onStart?() }
    @objc private func togglePauseClicked() { onTogglePause?() }
    @objc private func stopClicked() { onStop?() }
    @objc private func cancelClicked() { onCancel?() }
}
