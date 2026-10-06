import AppKit

/// 截图工具条代理：工具条按钮事件回调。
protocol ScreenshotToolbarDelegate: AnyObject {
    func toolbarDidSelect(tool: AnnotationType?)
    func toolbarDidSelectColor(_ color: AnnotationColor)
    func toolbarDidToggleCornerRadius()
    func toolbarDidToggleShadow()
    func toolbarDidSetShadowOpacity(_ opacity: CGFloat)
    func toolbarDidUndo()
    func toolbarDidRequestOCR()
    func toolbarDidRequestOCRAndCopy()
    func toolbarDidRequestDelay(seconds: Int)
    func toolbarDidCopy()
    func toolbarDidSave()
    func toolbarDidPin()
    func toolbarDidCancel()
    func toolbarDidScroll()
}

/// 浮动截图工具条：标注工具 + 颜色 + 操作按钮（复制/保存/贴图/取消）。
final class ScreenshotToolbar: NSWindow {

    weak var toolbarDelegate: ScreenshotToolbarDelegate?
    private var toolButtons: [AnnotationType?: NSButton] = [:]
    private var cornerButton: NSButton?
    private var canvasButton: NSButton?
    private var canvasPanel: NSPanel?
    private var morePanel: NSPanel?
    private var delayPanel: NSPanel?
    /// 子面板打开期间的点击外部关闭监控（本地+全局），全部关闭时移除
    private var dismissMonitors: (local: Any?, global: Any?)?
    private var shadowToggleButton: NSButton?
    private var shadowSlider: NSSlider?
    private var shadowLabel: NSTextField?
    private var paletteButton: NSButton?
    private var colorPanel: NSPanel?
    private var undoButton: NSButton?
    private(set) var selectedColor: AnnotationColor = .red

    init() {
        let frame = NSRect(x: 0, y: 0, width: 690, height: 48)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 工具条层级高于覆盖层(screenSaver)，防止用户点覆盖层画图时覆盖层置顶遮住工具条
        self.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovable = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.acceptsMouseMovedEvents = true

        buildUI()
    }


    private func buildUI() {
        let container = ToolbarContainerView(frame: contentView!.bounds)
        container.wantsLayer = true
        container.autoresizingMask = [.width, .height]
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(srgbRed: 0.89, green: 0.89, blue: 0.89, alpha: 0.98).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.black.withAlphaComponent(0.06).cgColor
        contentView = container

        var x: CGFloat = 8
        let y: CGFloat = 10
        let btnSize: CGFloat = 28

        // 圆角按钮（最左）：直接循环切换 0/8/16/24/32，按钮显示当前半径
        let cornerBtn = NSButton(frame: NSRect(x: x, y: y, width: 36, height: btnSize))
        cornerBtn.isBordered = false
        cornerBtn.wantsLayer = true
        cornerBtn.layer?.cornerRadius = 6
        cornerBtn.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
        cornerBtn.attributedTitle = NSAttributedString(string: "圆角", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
        ])
        cornerBtn.title = ""
        cornerBtn.toolTip = "圆角：点击循环切换半径"
        cornerBtn.target = self
        cornerBtn.action = #selector(cornerTapped)
        container.addSubview(cornerBtn)
        container.registerTooltipButton(cornerBtn, text: "圆角")
        cornerButton = cornerBtn
        x += 36 + 4

        // 选择工具（无标注）
        x = addToolButton(container, x: x, y: y, size: btnSize, tool: nil, symbol: "cursorarrow")

        // 标注工具
        x = addToolButton(container, x: x + 4, y: y, size: btnSize, tool: .rectangle, symbol: "square", tooltip: "形状")
        x = addToolButton(container, x: x + 4, y: y, size: btnSize, tool: .arrow, symbol: "arrow.up.right", tooltip: "箭头")
        x = addToolButton(container, x: x + 4, y: y, size: btnSize, tool: .text, symbol: "textformat", tooltip: "文案")
        x = addToolButton(container, x: x + 4, y: y, size: btnSize, tool: .mosaic, symbol: "square.dashed", tooltip: "马赛克")
        x = addToolButton(container, x: x + 4, y: y, size: btnSize, tool: .counter,
                          symbol: "number.square", tooltip: "序号标注（点击画布放置，重新选中复位为 1）")

        // 画布按钮：点击展开子面板（圆角 + 阴影）
        let cvBtn = NSButton(frame: NSRect(x: x + 6, y: y, width: btnSize, height: btnSize))
        cvBtn.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "画布")
        cvBtn.image?.isTemplate = true
        cvBtn.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        cvBtn.isBordered = false
        cvBtn.wantsLayer = true
        cvBtn.layer?.cornerRadius = 6
        cvBtn.title = ""
        cvBtn.target = self
        cvBtn.action = #selector(canvasTapped)
        container.addSubview(cvBtn)
        container.registerTooltipButton(cvBtn, text: "画布")
        canvasButton = cvBtn
        x += 6 + btnSize

        // 撤销按钮（撤销最后一个标注）
        let ub = NSButton(frame: NSRect(x: x + 4, y: y, width: btnSize, height: btnSize))
        ub.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "撤销")
        ub.image?.isTemplate = true
        ub.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        ub.isBordered = false
        ub.wantsLayer = true
        ub.layer?.cornerRadius = 6
        ub.title = ""
        ub.target = self
        ub.action = #selector(undoTapped)
        container.addSubview(ub)
        container.registerTooltipButton(ub, text: "撤销")
        undoButton = ub
        updateUndoButton(canUndo: false)
        x += 4 + btnSize

        // 更多工具按钮：点击展开子面板（识字/OCR 等）
        let moreBtn = NSButton(frame: NSRect(x: x + 4, y: y, width: btnSize, height: btnSize))
        moreBtn.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "更多")
        moreBtn.image?.isTemplate = true
        moreBtn.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        moreBtn.isBordered = false
        moreBtn.wantsLayer = true
        moreBtn.layer?.cornerRadius = 6
        moreBtn.title = ""
        moreBtn.target = self
        moreBtn.action = #selector(moreTapped)
        container.addSubview(moreBtn)
        container.registerTooltipButton(moreBtn, text: "更多")
        x += 4 + btnSize

        // 延时截图按钮：点击展开子面板（3s/5s/10s），倒计时结束抓新鲜帧
        let delayBtn = NSButton(frame: NSRect(x: x + 4, y: y, width: btnSize, height: btnSize))
        delayBtn.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "延时截图")
        delayBtn.image?.isTemplate = true
        delayBtn.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        delayBtn.isBordered = false
        delayBtn.wantsLayer = true
        delayBtn.layer?.cornerRadius = 6
        delayBtn.title = ""
        delayBtn.target = self
        delayBtn.action = #selector(delayTapped)
        container.addSubview(delayBtn)
        container.registerTooltipButton(delayBtn, text: "延时截图")
        x += 4 + btnSize

        // 分隔线
        x += 8
        let sep = NSView(frame: NSRect(x: x, y: 8, width: 1, height: 32))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        container.addSubview(sep)
        x += 8

        // 主题颜色按钮：点击弹出颜色选择面板（预设色 + 自定义）
        let pBtn = NSButton(frame: NSRect(x: x, y: y, width: 28, height: 28))
        pBtn.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "主题")
        pBtn.image?.isTemplate = true
        pBtn.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        pBtn.isBordered = false
        pBtn.wantsLayer = true
        pBtn.layer?.cornerRadius = 6
        pBtn.layer?.borderWidth = 1
        pBtn.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        pBtn.toolTip = "主题"
        pBtn.target = self
        pBtn.action = #selector(paletteTapped)
        container.addSubview(pBtn)
        container.registerTooltipButton(pBtn, text: "主题")
        paletteButton = pBtn
        x += 28
        selectColor(.red)

        // 画笔工具：自由绘制路径
        x = addToolButton(container, x: x + 4, y: y, size: btnSize, tool: .pen, symbol: "paintbrush", tooltip: "画笔")

        // 分隔线
        x += 4
        let sep2 = NSView(frame: NSRect(x: x, y: 8, width: 1, height: 32))
        sep2.wantsLayer = true
        sep2.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        container.addSubview(sep2)
        x += 8

        // 操作按钮（长截图图标用上下双向箭头，避免与「下载」的 arrow.down 混淆；
        // 注意 SF Symbol 正确名称为 arrow.up.arrow.down，arrow.up.and.down 在 macOS 上不存在）
        x = addIconButton(container, x: x, y: y, symbol: "arrow.up.arrow.down", tooltip: "长截图（滚动拼接）", action: #selector(scrollTapped), bgColor: .systemPurple)
        x = addIconButton(container, x: x + 4, y: y, symbol: "arrow.down", tooltip: "下载", action: #selector(saveTapped), bgColor: .systemGreen)
        x = addIconButton(container, x: x + 4, y: y, symbol: "pin", tooltip: "贴图", action: #selector(pinTapped), bgColor: .systemOrange)
        x = addIconButton(container, x: x + 4, y: y, symbol: "xmark", tooltip: "关闭", action: #selector(cancelTapped), bgColor: .systemRed)

        // 对勾按钮：复制到剪贴板（最常用，放最后方便点击）
        x = addIconButton(container, x: x + 6, y: y, symbol: "checkmark", tooltip: "复制", action: #selector(copyTapped), bgColor: .systemBlue)
    }

    private func addToolButton(_ container: NSView, x: CGFloat, y: CGFloat, size: CGFloat,
                               tool: AnnotationType?, symbol: String, tooltip: String? = nil) -> CGFloat {
        let btn = NSButton(frame: NSRect(x: x, y: y, width: size, height: size))
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        btn.image?.isTemplate = true
        btn.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.target = self
        btn.action = #selector(toolSelected(_:))
        btn.title = ""
        btn.tag = toolTag(tool)
        container.addSubview(btn)
        if let tooltip = tooltip, let tc = container as? ToolbarContainerView {
            tc.registerTooltipButton(btn, text: tooltip)
        }
        toolButtons[tool] = btn
        selectTool(tool)
        return x + size
    }

    /// 图标按钮（下载/复制等）：无边框图标 + 背景色 + 悬停提示注册。
    private func addIconButton(_ container: ToolbarContainerView, x: CGFloat, y: CGFloat,
                                symbol: String, tooltip: String, action: Selector,
                                bgColor: NSColor) -> CGFloat {
        let btn = NSButton(frame: NSRect(x: x, y: y, width: 28, height: 28))
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
        container.registerTooltipButton(btn, text: tooltip)
        return x + 28
    }

    // MARK: 动作

    @objc private func toolSelected(_ sender: NSButton) {
        let tool = toolFromTag(sender.tag)
        selectTool(tool)
        DiagLog.write("Toolbar.toolSelected: tool=\(String(describing: tool)) tag=\(sender.tag)")
        toolbarDelegate?.toolbarDidSelect(tool: tool)
    }

    @objc private func paletteTapped() {
        if colorPanel != nil { closeColorPanel(); return }
        showColorPanel()
    }

    private func showColorPanel() {
        let swatchSize: CGFloat = 28
        let spacing: CGFloat = 6
        let count = CGFloat(AnnotationColor.presets.count)
        let panelWidth = count * swatchSize + (count - 1) * spacing + 16
        let panelHeight: CGFloat = 68
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = NSColor(srgbRed: 0.89, green: 0.89, blue: 0.89, alpha: 0.98)
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true

        let content = NSView(frame: panel.contentView!.bounds)
        content.wantsLayer = true
        panel.contentView = content

        var sx: CGFloat = 8
        let sy: CGFloat = 34
        for color in AnnotationColor.presets {
            let swatch = NSButton(frame: NSRect(x: sx, y: sy, width: swatchSize, height: swatchSize))
            swatch.title = ""
            swatch.image = nil
            swatch.wantsLayer = true
            swatch.layer?.cornerRadius = swatchSize / 2
            swatch.layer?.backgroundColor = nsColor(color).cgColor
            swatch.isBordered = false
            swatch.tag = AnnotationColor.presets.firstIndex(of: color)! + 200
            swatch.target = self
            swatch.action = #selector(presetColorSelected(_:))
            content.addSubview(swatch)
            sx += swatchSize + spacing
        }

        let customBtn = NSButton(frame: NSRect(x: 8, y: 6, width: panelWidth - 16, height: 22))
        customBtn.title = ""
        customBtn.isBordered = false
        customBtn.attributedTitle = NSAttributedString(string: "自定义…", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
        ])
        customBtn.alignment = .center
        customBtn.target = self
        customBtn.action = #selector(customColorTapped)
        content.addSubview(customBtn)

        if let btn = paletteButton, let btnWin = btn.window {
            let btnInWin = btn.superview?.convert(btn.frame, to: nil) ?? btn.frame
            let origin = btnWin.frame.origin
            let btnScreen = btnInWin.offsetBy(dx: origin.x, dy: origin.y)
            let screenFrame = btnWin.screen?.frame ?? NSScreen.main?.frame ?? .zero
            var px = btnScreen.midX - panelWidth / 2
            var py = btnScreen.minY - panelHeight - 6
            if px < screenFrame.minX { px = screenFrame.minX }
            if px + panelWidth > screenFrame.maxX { px = screenFrame.maxX - panelWidth }
            if py < screenFrame.minY { py = btnScreen.maxY + 6 }
            panel.setFrameOrigin(NSPoint(x: px, y: py))
        }

        panel.orderFrontRegardless()
        colorPanel = panel
        updatePaletteSelection()
        updateDismissMonitor()
    }

    @objc private func presetColorSelected(_ sender: NSButton) {
        let idx = sender.tag - 200
        guard AnnotationColor.presets.indices.contains(idx) else { return }
        let color = AnnotationColor.presets[idx]
        selectColor(color)
        DiagLog.write("Toolbar.presetColorSelected: color=\(color)")
        toolbarDelegate?.toolbarDidSelectColor(color)
        closeColorPanel()
    }

    @objc private func customColorTapped() {
        closeColorPanel()
        let cp = NSColorPanel.shared
        cp.showsAlpha = false
        // 层级必须高于全屏截图覆盖层（screenSaver），否则颜色面板被遮挡看不到
        cp.level = NSWindow.Level(rawValue: ColorPanelPositioner.panelLevelRaw(
            overlayLevelRaw: NSWindow.Level.screenSaver.rawValue))
        NotificationCenter.default.addObserver(
            self, selector: #selector(colorPanelChanged),
            name: NSColorPanel.colorDidChangeNotification, object: cp)
        // 先定位再显示，避免系统重置位置
        positionColorPanel(cp)
        cp.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 显示后再定位一次，确保位置不被系统覆盖
        positionColorPanel(cp)
        DispatchQueue.main.async { [weak self] in
            self?.positionColorPanel(cp)
        }
    }

    private func positionColorPanel(_ cp: NSColorPanel) {
        guard let btn = paletteButton, let btnWin = btn.window else { return }
        let btnInWin = btn.superview?.convert(btn.frame, to: nil) ?? btn.frame
        let origin = btnWin.frame.origin
        let btnScreen = btnInWin.offsetBy(dx: origin.x, dy: origin.y)
        let screen = btnWin.screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? .zero
        let pos = ColorPanelPositioner.origin(
            buttonScreenFrame: btnScreen, screenFrame: screenFrame, panelSize: cp.frame.size)
        cp.setFrameOrigin(pos)
    }

    @objc private func colorPanelChanged() {
        let cp = NSColorPanel.shared
        let c = cp.color.usingColorSpace(.sRGB) ?? cp.color
        let custom = AnnotationColor.custom(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
        selectColor(custom)
        DiagLog.write("Toolbar.colorPanelChanged: custom color selected")
        toolbarDelegate?.toolbarDidSelectColor(custom)
    }

    func closeColorPanel() {
        colorPanel?.orderOut(nil)
        colorPanel = nil
        updateDismissMonitor()
    }

    func cleanupColorPanel() {
        closeColorPanel()
        NotificationCenter.default.removeObserver(
            self, name: NSColorPanel.colorDidChangeNotification, object: NSColorPanel.shared)
        NSColorPanel.shared.close()
        updateDismissMonitor()
    }

    /// 隐藏所有悬停提示窗口（截帧前调用，避免提示文字被截入画面）。
    func hideTooltips() {
        (contentView as? ToolbarContainerView)?.hideTooltip()
    }

    @objc private func copyTapped() { toolbarDelegate?.toolbarDidCopy() }
    @objc private func saveTapped() { toolbarDelegate?.toolbarDidSave() }
    @objc private func pinTapped() { toolbarDelegate?.toolbarDidPin() }
    @objc private func cancelTapped() { toolbarDelegate?.toolbarDidCancel() }
    @objc private func scrollTapped() { toolbarDelegate?.toolbarDidScroll() }
    @objc private func cornerTapped() { toolbarDelegate?.toolbarDidToggleCornerRadius() }

    @objc private func canvasTapped() {
        if canvasPanel != nil { closeCanvasPanel(); return }
        showCanvasPanel()
    }

    @objc private func moreTapped() {
        if morePanel != nil { closeMorePanel(); return }
        showMorePanel()
    }

    @objc private func ocrTapped() {
        closeMorePanel()
        toolbarDelegate?.toolbarDidRequestOCR()
    }

    @objc private func ocrCopyTapped() {
        closeMorePanel()
        toolbarDelegate?.toolbarDidRequestOCRAndCopy()
    }

    // MARK: - 延时截图子面板

    @objc private func delayTapped() {
        if delayPanel != nil { closeDelayPanel(); return }
        showDelayPanel()
    }

    /// 显示延时档位子面板：3s / 5s / 10s 横排三个按钮，tag 即秒数。
    private func showDelayPanel() {
        let btnWidth: CGFloat = 40
        let spacing: CGFloat = 6
        let panelWidth = CGFloat(3) * btnWidth + CGFloat(2) * spacing + 16
        let panelHeight: CGFloat = 44
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true

        let card = NSView(frame: panel.contentView!.bounds)
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor(srgbRed: 0.89, green: 0.89, blue: 0.89, alpha: 0.98).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.black.withAlphaComponent(0.06).cgColor
        panel.contentView?.addSubview(card)

        var dx: CGFloat = 8
        for seconds in [3, 5, 10] {
            let btn = NSButton(frame: NSRect(x: dx, y: 8, width: btnWidth, height: 28))
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
            btn.isBordered = false
            btn.attributedTitle = NSAttributedString(string: "\(seconds)s", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
            ])
            btn.title = ""
            btn.tag = seconds
            btn.toolTip = "\(seconds) 秒后截取当前画面"
            btn.target = self
            btn.action = #selector(delaySelected(_:))
            card.addSubview(btn)
            dx += btnWidth + spacing
        }

        // 定位子面板在工具栏下方（与其他子面板一致）
        let screenFrame = self.screen?.frame ?? NSScreen.main?.frame ?? .zero
        let pos = CanvasPanelPositioner.position(
            toolbarFrame: self.frame,
            panelSize: CGSize(width: panelWidth, height: panelHeight),
            screenFrame: screenFrame
        )
        panel.setFrameOrigin(pos)

        panel.orderFrontRegardless()
        delayPanel = panel
        updateDismissMonitor()
    }

    @objc private func delaySelected(_ sender: NSButton) {
        closeDelayPanel()
        toolbarDelegate?.toolbarDidRequestDelay(seconds: sender.tag)
    }

    func closeDelayPanel() {
        delayPanel?.orderOut(nil)
        delayPanel = nil
        updateDismissMonitor()
    }

    // MARK: - 更多工具子面板

    /// 显示更多工具子面板：识字（弹结果面板）+ 识字并复制（静默直达剪贴板）。
    private func showMorePanel() {
        let panelWidth: CGFloat = 120
        let panelHeight: CGFloat = 44
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true

        let card = NSView(frame: panel.contentView!.bounds)
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor(srgbRed: 0.89, green: 0.89, blue: 0.89, alpha: 0.98).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.black.withAlphaComponent(0.06).cgColor
        panel.contentView?.addSubview(card)

        // 识字按钮（OCR 文字识别，弹结果面板）
        let ocrBtn = NSButton(frame: NSRect(x: 8, y: 8, width: 28, height: 28))
        ocrBtn.image = NSImage(systemSymbolName: "doc.text.viewfinder", accessibilityDescription: "识字")
        ocrBtn.image?.isTemplate = true
        ocrBtn.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        ocrBtn.isBordered = false
        ocrBtn.wantsLayer = true
        ocrBtn.layer?.cornerRadius = 6
        ocrBtn.title = ""
        ocrBtn.target = self
        ocrBtn.action = #selector(ocrTapped)
        card.addSubview(ocrBtn)

        // 识字并复制按钮（静默路径：结果直接写剪贴板 + Toast，不弹面板）
        let ocrCopyBtn = NSButton(frame: NSRect(x: 48, y: 8, width: 28, height: 28))
        ocrCopyBtn.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "识字并复制")
        ocrCopyBtn.image?.isTemplate = true
        ocrCopyBtn.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        ocrCopyBtn.isBordered = false
        ocrCopyBtn.wantsLayer = true
        ocrCopyBtn.layer?.cornerRadius = 6
        ocrCopyBtn.title = ""
        ocrCopyBtn.target = self
        ocrCopyBtn.action = #selector(ocrCopyTapped)
        card.addSubview(ocrCopyBtn)

        // 定位子面板在工具栏下方
        let screenFrame = self.screen?.frame ?? NSScreen.main?.frame ?? .zero
        let pos = CanvasPanelPositioner.position(
            toolbarFrame: self.frame,
            panelSize: CGSize(width: panelWidth, height: panelHeight),
            screenFrame: screenFrame
        )
        panel.setFrameOrigin(pos)

        panel.orderFrontRegardless()
        morePanel = panel
        updateDismissMonitor()
    }

    func closeMorePanel() {
        morePanel?.orderOut(nil)
        morePanel = nil
        updateDismissMonitor()
    }

    // MARK: - 子面板点击外部关闭

    /// 当前打开的所有子面板。
    private var openPanels: [NSPanel] { [morePanel, delayPanel, canvasPanel, colorPanel].compactMap { $0 } }

    /// 任一子面板打开/关闭后同步监控状态：有面板时安装，全关时移除。
    private func updateDismissMonitor() {
        if openPanels.isEmpty {
            if let local = dismissMonitors?.local { NSEvent.removeMonitor(local) }
            if let global = dismissMonitors?.global { NSEvent.removeMonitor(global) }
            dismissMonitors = nil
        } else if dismissMonitors == nil {
            let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handleOutsideClick()
                return event  // 不吞事件，点击照常传递
            }
            let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                self?.handleOutsideClick()
            }
            dismissMonitors = (local, global)
        }
    }

    /// 点击位置不在任何子面板与工具条内 → 关闭全部子面板。
    private func handleOutsideClick() {
        let panels = openPanels
        guard !panels.isEmpty else { return }
        let frames = panels.map { $0.frame }
        if PanelDismissal.shouldDismiss(click: NSEvent.mouseLocation, panelFrames: frames, toolbarFrame: frame) {
            closeAllPanels()
        }
    }

    /// 关闭全部子面板（更多/延时/画布/颜色），截图会话结束时必须调用，
    /// 防止面板在工具条窗口销毁后成为孤儿窗口残留屏幕。
    func closeAllPanels() {
        closeCanvasPanel()
        closeMorePanel()
        closeDelayPanel()
        cleanupColorPanel()
    }

    @objc private func shadowToggled() {
        toolbarDelegate?.toolbarDidToggleShadow()
    }

    @objc private func shadowSliderChanged() {
        let opacity = shadowSlider?.doubleValue ?? 0.16
        toolbarDelegate?.toolbarDidSetShadowOpacity(CGFloat(opacity))
    }
    @objc private func undoTapped() { toolbarDelegate?.toolbarDidUndo() }

    // MARK: 工具状态

    func selectTool(_ tool: AnnotationType?) {
        for (t, btn) in toolButtons {
            btn.layer?.backgroundColor = (t == tool)
                ? NSColor.black.withAlphaComponent(0.12).cgColor
                : NSColor.black.withAlphaComponent(0.04).cgColor
        }
    }

    /// 更新当前选中颜色，同步调色板按钮背景色。
    func selectColor(_ color: AnnotationColor) {
        selectedColor = color
        paletteButton?.layer?.backgroundColor = nsColor(color).cgColor
        updatePaletteSelection()
    }

    /// 高亮颜色面板中当前选中的预设色块（白色描边）。
    private func updatePaletteSelection() {
        guard let content = colorPanel?.contentView else { return }
        for sv in content.subviews {
            guard let btn = sv as? NSButton, btn.tag >= 200 else { continue }
            let idx = btn.tag - 200
            guard AnnotationColor.presets.indices.contains(idx) else { continue }
            let isSelected = AnnotationColor.presets[idx] == selectedColor
            btn.layer?.borderWidth = isSelected ? 2.5 : 0
            btn.layer?.borderColor = NSColor.white.cgColor
        }
    }

    /// 更新撤销按钮的可用状态（无可撤销标注时置灰）。
    func updateUndoButton(canUndo: Bool) {
        undoButton?.isEnabled = canUndo
        undoButton?.contentTintColor = canUndo ? .white : NSColor.black.withAlphaComponent(0.12)
    }

    /// 更新圆角按钮的视觉状态（激活时高亮并显示当前半径）。
    func updateCornerRadius(_ radius: CGFloat) {
        let active = CornerRounding.isEnabled(radius)
        cornerButton?.layer?.backgroundColor = active
            ? NSColor.systemBlue.withAlphaComponent(0.15).cgColor
            : NSColor.black.withAlphaComponent(0.04).cgColor
        let title = active ? "圆\(Int(radius))" : "圆角"
        cornerButton?.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
        ])
    }

    // MARK: - 画布子面板

    /// 显示画布子面板（阴影开关 + 透明度；圆角已移至工具条最左按钮）。
    private func showCanvasPanel() {
        let panelWidth: CGFloat = 254
        let panelHeight: CGFloat = 44
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true

        let card = NSView(frame: panel.contentView!.bounds)
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor(srgbRed: 0.89, green: 0.89, blue: 0.89, alpha: 0.98).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.black.withAlphaComponent(0.06).cgColor
        panel.contentView?.addSubview(card)

        // 阴影开关按钮
        let shBtn = NSButton(frame: NSRect(x: 8, y: 8, width: 50, height: 28))
        shBtn.wantsLayer = true
        shBtn.layer?.cornerRadius = 6
        shBtn.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
        shBtn.isBordered = false
        shBtn.attributedTitle = NSAttributedString(string: "阴影", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
        ])
        shBtn.title = ""
        shBtn.target = self
        shBtn.action = #selector(shadowToggled)
        card.addSubview(shBtn)
        shadowToggleButton = shBtn

        // 阴影透明度标签
        let sLabel = NSTextField(labelWithString: "16%")
        sLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sLabel.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        sLabel.alignment = .center
        sLabel.frame = NSRect(x: 206, y: 14, width: 40, height: 16)
        card.addSubview(sLabel)
        shadowLabel = sLabel

        // 阴影透明度滑块
        let slider = NSSlider(frame: NSRect(x: 66, y: 14, width: 135, height: 16))
        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = 0.16
        slider.target = self
        slider.action = #selector(shadowSliderChanged)
        slider.controlSize = .small
        card.addSubview(slider)
        shadowSlider = slider

        // 定位子面板在工具栏下方（基于工具栏窗口 frame，避免与工具栏重叠）
        if let btn = canvasButton, let btnWin = btn.window {
            let screenFrame = btnWin.screen?.frame ?? NSScreen.main?.frame ?? .zero
            let pos = CanvasPanelPositioner.position(
                toolbarFrame: btnWin.frame,
                panelSize: CGSize(width: panelWidth, height: panelHeight),
                screenFrame: screenFrame
            )
            panel.setFrameOrigin(pos)
        }

        panel.orderFrontRegardless()
        canvasPanel = panel
        updateCanvasShadowButton(enabled: true)
        updateDismissMonitor()
    }

    func closeCanvasPanel() {
        canvasPanel?.orderOut(nil)
        canvasPanel = nil
        updateDismissMonitor()
    }

    /// 更新阴影开关按钮状态。
    func updateCanvasShadowButton(enabled: Bool) {
        shadowToggleButton?.layer?.backgroundColor = enabled
            ? NSColor.systemBlue.withAlphaComponent(0.15).cgColor
            : NSColor.black.withAlphaComponent(0.04).cgColor
    }

    /// 更新阴影透明度显示。
    func updateCanvasShadowOpacity(_ opacity: CGFloat) {
        shadowSlider?.doubleValue = Double(opacity)
        let pct = Int((opacity * 100).rounded())
        shadowLabel?.stringValue = "\(pct)%"
    }

    private func toolTag(_ tool: AnnotationType?) -> Int {
        guard let tool = tool else { return 0 }
        return AnnotationType.allCases.firstIndex(of: tool)! + 1
    }

    private func toolFromTag(_ tag: Int) -> AnnotationType? {
        guard tag > 0 else { return nil }
        let idx = tag - 1
        return AnnotationType.allCases.indices.contains(idx) ? AnnotationType.allCases[idx] : nil
    }

    private func nsColor(_ color: AnnotationColor) -> NSColor {
        let rgb = color.rgbComponents
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

}

/// 工具条内容视图：强制显示箭头光标，并管理图标按钮的悬停提示。
/// nonactivatingPanel 下 cursorRect 与 mouseEntered 不可靠，改用 mouseMoved
/// tracking area（已验证有效）检测悬停，提示用独立小窗口显示避免裁剪。
final class ToolbarContainerView: NSView {
    private var tooltipButtons: [(button: NSButton, text: String)] = []
    private var hoverState = ToolbarHoverState()
    private var tooltipWindow: NSPanel?

    /// 注册一个图标按钮及其悬停提示文本。
    func registerTooltipButton(_ button: NSButton, text: String) {
        tooltipButtons.append((button, text))
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

    /// 鼠标在工具条任意位置（含子视图）移动时强制箭头光标，并更新图标按钮悬停提示。
    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        updateTooltip(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { hideTooltip() }
    }

    private func updateTooltip(with event: NSEvent) {
        guard !tooltipButtons.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        let matched = tooltipButtons.first(where: { $0.button.frame.contains(point) })?.text
        guard hoverState.update(matchedTooltip: matched) else { return }
        if let text = hoverState.currentTooltip,
           let button = tooltipButtons.first(where: { $0.text == text })?.button {
            showTooltip(text: text, for: button)
        } else {
            hideTooltip()
        }
    }

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

        let labelView = TooltipLabelView(text: text, font: font)
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

/// 提示标签视图：浅色圆角背景 + 垂直居中深色文字。
/// 使用 TooltipTextCentering 计算基线 y，修正 NSTextField 默认渲染偏上。
private final class TooltipLabelView: NSView {
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
        let baselineY = TooltipTextCentering.baselineY(
            containerHeight: bounds.height,
            ascender: font.ascender,
            descender: font.descender
        )
        (text as NSString).draw(
            at: NSPoint(x: bounds.midX - textWidth / 2, y: baselineY),
            withAttributes: attrs
        )
    }
}
