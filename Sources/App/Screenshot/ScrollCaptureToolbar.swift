import AppKit

/// 滚动控制工具条代理：按钮事件统一回调（工具条自身不持有截取业务状态，
/// 开始/停止/完成的实际执行由集成方实现）。
public protocol ScrollCaptureToolbarDelegate: AnyObject {
    /// 开始/停止按钮：运行态切换（含自动滚动的启动，由实现方驱动）。
    func scrollToolbarDidToggleRun(_ toolbar: ScrollCaptureToolbar)
    /// 速度档位切换（点击循环 slow → medium → fast）。
    func scrollToolbarDidSelectSpeed(_ toolbar: ScrollCaptureToolbar, level: ScrollAutoSpeedLevel)
    /// 完成按钮：停止截取并生成结果窗。
    func scrollToolbarDidFinish(_ toolbar: ScrollCaptureToolbar)
    /// 取消按钮：放弃本次长截图。
    func scrollToolbarDidCancel(_ toolbar: ScrollCaptureToolbar)
}

/// 滚动长截图控制工具条（独立类，替代旧内嵌于 ScreenshotCoordinator 的滚动工具栏）。
/// - 按钮全部带悬停提示（本次修复点之一：旧工具条按钮无任何提示，复制按钮被误当「保存」）；
/// - 不设复制按钮——结果出口统一移至 `ScrollResultPanel`；
/// - 视觉复刻旧 addScrollButton：28pt 图标按钮 + 圆角 6 + 彩色底 + 白色模板图标；
/// - 位置规则沿用旧 showScrollToolbar：选区下方优先，放不下则上方，横向夹屏。
public final class ScrollCaptureToolbar: NSPanel {

    public weak var toolbarDelegate: ScrollCaptureToolbarDelegate?

    // MARK: UI 引用

    private var container: ScrollToolbarContainerView!
    private var runButton: NSButton!
    private var speedButton: NSButton!
    private var finishButton: NSButton!
    private var cancelButton: NSButton!
    private var counterLabel: NSTextField!

    // MARK: 状态

    private var isRunning = false
    /// 当前速度档位（初始 medium，集成方可用 setSpeed 覆盖同步真实档位）。
    private var speedLevel: ScrollAutoSpeedLevel = .medium

    // MARK: 布局常量

    private static let buttonSize: CGFloat = 28
    private static let speedButtonWidth: CGFloat = 34
    private static let edgePadding: CGFloat = 12
    /// 计数标签固定宽（「已捕获 12800px · 42帧」量级，超长截断）。
    private static let counterWidth: CGFloat = 132
    /// 预览窗建议宽度（竖向窄条）。
    private static let previewHostWidth: CGFloat = 72
    /// 预览窗建议最大高度（不超过 1.6×屏高，兼顾屏幕空间取整值）。
    private static let previewHostMaxHeight: CGFloat = 300
    /// 常驻提示文案（工具条顶部一行小字）。
    private static let hintText = "选区应完全可滚动，避开固定侧栏与滚动条；自动滚动到底后自动完成"

    // MARK: 生命周期

    public init() {
        let size = Self.panelSize()
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // 层级与旧滚动工具条一致：高于截图覆盖层(screenSaver)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = false
        acceptsMouseMovedEvents = true

        buildUI(size: size)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: 对外 API

    /// 显示工具条：选区下方优先，放不下则上方；横向、纵向均夹到屏幕内。
    /// `selectionRect` 为屏幕本地坐标（与旧 showScrollToolbar 相同口径）。
    public func show(relativeTo selectionRect: NSRect, on screen: NSScreen) {
        let size = frame.size
        let screenFrame = screen.frame
        var px = selectionRect.midX - size.width / 2 + screenFrame.origin.x
        var py = selectionRect.minY - size.height - 8 + screenFrame.origin.y
        if py < screenFrame.minY {
            py = selectionRect.maxY + 8 + screenFrame.origin.y
        }
        px = max(screenFrame.minX, min(px, screenFrame.maxX - size.width))
        py = max(screenFrame.minY, min(py, screenFrame.maxY - size.height))
        setFrameOrigin(NSPoint(x: px, y: py))
        orderFrontRegardless()
        DiagLog.write("ScrollCaptureToolbar shown at (\(px), \(py)) selection=\(selectionRect)")
    }

    /// 切换开始/停止按钮态：play.fill(绿) ↔ stop.fill(橙)，悬停提示同步更新。
    public func setRunning(_ running: Bool) {
        isRunning = running
        let symbol = running ? "stop.fill" : "play.fill"
        let tooltip = running ? "停止" : "开始自动滚动"
        runButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        runButton.image?.isTemplate = true
        runButton.layer?.backgroundColor = (running ? NSColor.systemOrange : NSColor.systemGreen).cgColor
        runButton.toolTip = tooltip
        container?.setTooltip(tooltip, for: runButton)
    }

    /// 更新速度档位按钮显示（「1×/2×/3×」）。
    public func setSpeed(_ level: ScrollAutoSpeedLevel) {
        speedLevel = level
        speedButton.attributedTitle = NSAttributedString(
            string: Self.speedText(level),
            attributes: Self.speedTitleAttributes
        )
    }

    /// 更新计数（与实时预览条同格式：「已捕获 高度px · N帧」）。
    public func updateCounter(frames: Int, pixelHeight: Int) {
        counterLabel.stringValue = ScrollCaptureCounterText.text(frames: frames, pixelHeight: pixelHeight)
    }

    /// LiveStitchPreviewView 建议放置区域（工具条左侧，底边对齐，向上生长）：
    /// 左侧放不下时退到右侧；高度向上不超过屏幕顶。`show(relativeTo:on:)` 之后有效，
    /// 显示前返回 .zero。
    public var previewHostFrame: NSRect {
        let screenFrame = screen?.frame ?? NSScreen.main?.frame ?? .zero
        guard screenFrame.width > 0, frame.width > 0 else { return .zero }
        let hostWidth = Self.previewHostWidth
        var x = frame.minX - 8 - hostWidth
        if x < screenFrame.minX {
            x = frame.maxX + 8
        }
        x = max(screenFrame.minX, min(x, screenFrame.maxX - hostWidth))
        let y = frame.minY
        let desiredHeight = min(screenFrame.height * 1.6, Self.previewHostMaxHeight)
        var height = min(desiredHeight, screenFrame.maxY - y - 8)
        height = max(height, 48)
        height = min(height, max(48, screenFrame.maxY - y - 2))
        return NSRect(x: x, y: y, width: hostWidth, height: height)
    }

    /// 是否处于运行态（供集成方核对，避免重复启动）。
    public var running: Bool { isRunning }

    /// 当前速度档位。
    public var currentSpeed: ScrollAutoSpeedLevel { speedLevel }

    // MARK: 档位换算

    /// 档位显示文本：slow→1×、medium→2×、fast→3×。
    static func speedText(_ level: ScrollAutoSpeedLevel) -> String {
        switch level {
        case .slow: return "1×"
        case .medium: return "2×"
        case .fast: return "3×"
        }
    }

    /// 点击循环下一档：slow → medium → fast → slow。
    static func nextSpeed(from level: ScrollAutoSpeedLevel) -> ScrollAutoSpeedLevel {
        switch level {
        case .slow: return .medium
        case .medium: return .fast
        case .fast: return .slow
        }
    }

    private static let speedTitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.white
    ]

    // MARK: 面板尺寸

    /// 面板尺寸：宽度取「提示单行宽度」与「计数 + 按钮行宽度」的较大者；高度 = 提示行 + 按钮行。
    private static func panelSize() -> NSSize {
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular)
        ]
        let hintWidth = ceil((hintText as NSString).size(withAttributes: hintAttrs).width)
        let buttonRowWidth = counterWidth + 10
            + buttonSize + 4 + speedButtonWidth + 10
            + buttonSize + 4 + buttonSize
        let width = max(hintWidth, buttonRowWidth) + edgePadding * 2
        let height: CGFloat = 10 + 16 + 6 + buttonSize + 10
        return NSSize(width: width, height: height)
    }

    // MARK: 构建 UI

    private func buildUI(size: NSSize) {
        let c = ScrollToolbarContainerView(frame: NSRect(origin: .zero, size: size))
        c.wantsLayer = true
        c.autoresizingMask = [.width, .height]
        // 深色圆角卡片：复刻旧滚动工具条背景
        c.layer?.cornerRadius = 12
        c.layer?.masksToBounds = true
        c.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.96).cgColor
        c.layer?.borderWidth = 1
        c.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        contentView = c
        container = c

        // 常驻提示小字（顶部一行）
        let hint = NSTextField(labelWithString: Self.hintText)
        hint.font = .systemFont(ofSize: 11, weight: .regular)
        hint.textColor = NSColor(white: 0.7, alpha: 1)
        hint.lineBreakMode = .byTruncatingTail
        hint.frame = NSRect(x: Self.edgePadding,
                            y: size.height - 10 - 16,
                            width: size.width - Self.edgePadding * 2,
                            height: 16)
        c.addSubview(hint)

        // 计数标签（按钮行左侧，与旧工具条 frameLabel 同款灰白）
        let counter = NSTextField(labelWithString: ScrollCaptureCounterText.text(frames: 0, pixelHeight: 0))
        counter.font = .systemFont(ofSize: 11, weight: .medium)
        counter.textColor = .white
        counter.lineBreakMode = .byTruncatingTail
        counter.frame = NSRect(x: Self.edgePadding, y: 14, width: Self.counterWidth, height: 16)
        c.addSubview(counter)
        counterLabel = counter

        // 按钮行（右侧，从右往左布）：取消 | 完成 ‖ 档位 | 开始/停止
        let btnY: CGFloat = 12
        var x = size.width - Self.edgePadding - Self.buttonSize
        cancelButton = makeIconButton(symbol: "xmark", bgColor: .systemRed,
                                      tooltip: "取消长截图", action: #selector(cancelTapped))
        cancelButton.frame = NSRect(x: x, y: btnY, width: Self.buttonSize, height: Self.buttonSize)

        x -= Self.buttonSize + 4
        finishButton = makeIconButton(symbol: "checkmark", bgColor: .systemBlue,
                                      tooltip: "完成并生成结果", action: #selector(finishTapped))
        finishButton.frame = NSRect(x: x, y: btnY, width: Self.buttonSize, height: Self.buttonSize)

        // 分隔线：区分「运行控制组」与「完成组」
        x -= 10 + 1
        let sep = NSBox(frame: NSRect(x: x, y: btnY + 2, width: 1, height: Self.buttonSize - 4))
        sep.boxType = .separator
        c.addSubview(sep)

        x -= Self.speedButtonWidth
        speedButton = NSButton(frame: NSRect(x: x, y: btnY, width: Self.speedButtonWidth, height: Self.buttonSize))
        speedButton.isBordered = false
        speedButton.wantsLayer = true
        speedButton.layer?.cornerRadius = 6
        speedButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        speedButton.attributedTitle = NSAttributedString(string: Self.speedText(speedLevel),
                                                         attributes: Self.speedTitleAttributes)
        speedButton.toolTip = "自动滚动速度"
        speedButton.target = self
        speedButton.action = #selector(speedTapped)
        c.addSubview(speedButton)
        c.setTooltip("自动滚动速度", for: speedButton)

        x -= Self.buttonSize + 4
        runButton = makeIconButton(symbol: "play.fill", bgColor: .systemGreen,
                                   tooltip: "开始自动滚动", action: #selector(runTapped))
        runButton.frame = NSRect(x: x, y: btnY, width: Self.buttonSize, height: Self.buttonSize)
    }

    /// 图标按钮：复刻旧 addScrollButton 视觉（28pt 无边框图标 + 圆角 6 + 彩色底 + 白色模板图），
    /// 并注册自绘悬停提示（nonactivatingPanel 下系统 toolTip 不可靠，见主工具条同款处理）。
    private func makeIconButton(symbol: String, bgColor: NSColor,
                                tooltip: String, action: Selector) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        btn.image?.isTemplate = true
        btn.contentTintColor = .white
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.layer?.backgroundColor = bgColor.cgColor
        btn.toolTip = tooltip
        btn.target = self
        btn.action = action
        container.addSubview(btn)
        container.setTooltip(tooltip, for: btn)
        return btn
    }

    // MARK: 按钮动作（统一走 delegate）

    @objc private func runTapped() {
        DiagLog.write("ScrollCaptureToolbar.runTapped: running=\(isRunning)")
        toolbarDelegate?.scrollToolbarDidToggleRun(self)
    }

    @objc private func speedTapped() {
        let next = Self.nextSpeed(from: speedLevel)
        setSpeed(next)
        DiagLog.write("ScrollCaptureToolbar.speedTapped: next=\(next)")
        toolbarDelegate?.scrollToolbarDidSelectSpeed(self, level: next)
    }

    @objc private func finishTapped() {
        DiagLog.write("ScrollCaptureToolbar.finishTapped")
        toolbarDelegate?.scrollToolbarDidFinish(self)
    }

    @objc private func cancelTapped() {
        DiagLog.write("ScrollCaptureToolbar.cancelTapped")
        toolbarDelegate?.scrollToolbarDidCancel(self)
    }
}

// MARK: - 滚动工具条内容视图（自绘悬停提示）

/// 滚动工具条内容视图：深色卡片 + 强制箭头光标 + 自绘悬停提示。
/// 复刻主工具条 ToolbarContainerView 的提示机制（nonactivatingPanel 下
/// cursorRect 与 mouseEntered 不可靠，改用 mouseMoved tracking area），
/// 额外支持运行态更新提示文案（开始↔停止）。
private final class ScrollToolbarContainerView: NSView {

    private var tooltipEntries: [(button: NSButton, text: String)] = []
    private var hoverState = ScrollToolbarHoverState()
    private var tooltipWindow: NSPanel?

    /// 注册/更新按钮的悬停提示文本（同一按钮重复调用即覆盖，供运行态切换）。
    func setTooltip(_ text: String, for button: NSButton) {
        if let idx = tooltipEntries.firstIndex(where: { $0.button === button }) {
            tooltipEntries[idx].text = text
        } else {
            tooltipEntries.append((button, text))
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: NSCursor.arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        let point = convert(event.locationInWindow, from: nil)
        let matched = tooltipEntries.first(where: { $0.button.frame.contains(point) })?.text
        guard hoverState.update(matchedTooltip: matched) else { return }
        if let text = hoverState.currentTooltip,
           let entry = tooltipEntries.first(where: { $0.text == text }) {
            showTooltip(text: text, for: entry.button)
        } else {
            hideTooltip()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { hideTooltip() }
    }

    /// 显示提示小窗（浅色圆角卡片，与主工具条提示同款视觉）。
    private func showTooltip(text: String, for button: NSButton) {
        hideTooltip()
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let labelSize = CGSize(width: ceil(textSize.width), height: ceil(textSize.height))
        let buttonInWindow = button.superview?.convert(button.frame, to: nil) ?? button.frame
        let winOrigin = button.window?.frame.origin ?? .zero
        let buttonScreen = buttonInWindow.offsetBy(dx: winOrigin.x, dy: winOrigin.y)
        let screenFrame = button.window?.screen?.frame ?? NSScreen.main?.frame ?? .zero
        let frame = CopyButtonTooltip.windowFrame(
            buttonScreenFrame: buttonScreen, labelSize: labelSize, screenFrame: screenFrame)

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false

        let labelView = ScrollTooltipLabelView(text: text, font: font)
        labelView.frame = panel.contentView!.bounds
        labelView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(labelView)

        panel.orderFrontRegardless()
        tooltipWindow = panel
    }

    func hideTooltip() {
        tooltipWindow?.orderOut(nil)
        tooltipWindow = nil
    }
}

/// 悬停状态机：目标变化才刷新；进入新目标需连续两次 mouseMoved 才弹出（轻防抖）。
private struct ScrollToolbarHoverState {
    private(set) var currentTooltip: String?
    private var pending: String?
    private var hits = 0

    /// 更新当前悬停目标。返回 true 表示需要刷新提示窗口。
    @discardableResult
    mutating func update(matchedTooltip: String?) -> Bool {
        if matchedTooltip != pending {
            pending = matchedTooltip
            hits = 0
            // 离开按钮：立即隐藏旧提示
            if matchedTooltip == nil, currentTooltip != nil {
                currentTooltip = nil
                return true
            }
            return false
        }
        hits += 1
        guard let target = matchedTooltip, target != currentTooltip, hits >= 2 else { return false }
        currentTooltip = target
        return true
    }
}

/// 提示标签视图：浅色圆角背景 + 垂直居中深色文字（复刻主工具条 TooltipLabelView）。
private final class ScrollTooltipLabelView: NSView {
    private let text: String
    private let font: NSFont

    init(text: String, font: NSFont) {
        self.text = text
        self.font = font
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor(srgbRed: 0.89, green: 0.89, blue: 0.89, alpha: 0.98).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.withAlphaComponent(0.06).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
        ]
        let textWidth = (text as NSString).size(withAttributes: attrs).width
        // 垂直居中：先在行高内下移底边距，再抬升 descender 对应的高度得到基线 y
        let baselineY = (bounds.height - (font.ascender - font.descender)) / 2 - font.descender
        (text as NSString).draw(
            at: NSPoint(x: bounds.midX - textWidth / 2, y: baselineY),
            withAttributes: attrs
        )
    }
}
