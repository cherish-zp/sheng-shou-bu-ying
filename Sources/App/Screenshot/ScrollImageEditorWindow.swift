import AppKit
import CoreGraphics

/// 编辑器标注类型。自足定义而未复用 AnnotationType，原因：
/// 1. AnnotationType 不含椭圆（冻结需求要求矩形/椭圆）；
/// 2. 覆盖层文字标注绑定固定 16pt 视图字号，而编辑器坐标在图像像素空间，
///    字号/线宽需按图像分辨率缩放，语义不同。
private enum EditorTool: Int {
    case pen = 1, rectangle, ellipse, arrow, text, mosaic
}

/// 编辑器标注：坐标记录在图像像素空间（原点左上、y 向下），与视图缩放无关。
/// - 矩形/椭圆/马赛克/箭头：points[0] 起点、points[1] 对角点
/// - 画笔：points 为自由路径点序列
/// - 文字：points[0] 左上角定位点，text 存内容
private struct EditorAnnotation {
    var type: EditorTool
    var points: [CGPoint]
    var text: String?
    var color: AnnotationColor
    var strokeWidthPx: CGFloat
    var fontSizePx: CGFloat
}

/// 长图标注编辑器：静态长图 + 画笔/矩形/椭圆/箭头/文字/马赛克 + 颜色/粗细/撤销。
///
/// 架构要点：
/// - 画布为 NSScrollView 内的 flipped 视图，适配宽度显示；缩放用 NSScrollView
///   内置 magnification（捏合 / ⌘+滚轮 / 工具条 +− 按钮），不改 documentView 尺寸；
/// - 标注以像素坐标存储（缩放无关），线宽与字号在创建时按 refScale 换算为像素值；
/// - 画布预览与最终位图合成共用同一套绘制函数（同一 flipped 像素坐标口径），
///   保证所见即所得；
/// - 大图内存策略：不做全图离屏缓存，马赛克仅缓存一张极小的整图缩略图
///   （无插值放大产生块状感）；合成时一次性分配整图 RGBA 位图（与拼接产物
///   同量级），完成后立即释放上下文。
final class ScrollImageEditorWindow: NSPanel {

    var onComplete: ((NSImage) -> Void)?
    private var onCancel: (() -> Void)?

    private let sourceCGImage: CGImage
    private let sourceDisplaySize: NSSize
    private var annotations: [EditorAnnotation] = []
    private var drawingAnnotation: EditorAnnotation?
    private var currentTool: EditorTool = .pen
    private var currentColor: AnnotationColor = .red
    /// 粗细档位下标（细/中/粗）。
    private var strokeWidthIndex = 1

    /// 粗细基准（适配宽度下的显示点数）：细/中/粗。
    private static let strokeWidths: [CGFloat] = [2, 4, 8]
    /// 文字字号基准（适配宽度下的显示点数）。
    private static let fontSizes: [CGFloat] = [16, 22, 30]

    /// 像素/显示点比例（适配宽度时）：粗细与字号按此换算到像素空间。
    private let refScale: CGFloat
    /// 当前显示比例：画布点 → 图像像素。
    private var displayScale: CGFloat {
        let w = canvasView?.bounds.width ?? 0
        return w > 0 ? w / CGFloat(sourceCGImage.width) : 1
    }

    private var canvasView: EditorCanvasView!
    private var canvasScrollView: NSScrollView!
    private var toolbarContainer: ToolbarContainerView!
    private var toolButtons: [EditorTool: NSButton] = [:]
    private var widthButtons: [NSButton] = []
    private var colorButtons: [NSButton] = []
    private var undoButton: NSButton?
    private var activeTextField: NSTextField?
    private var pendingTextPoint: CGPoint = .zero
    private var escMonitor: Any?
    /// 马赛克用整图缩略图（惰性生成：仅首次使用马赛克时降采样一次）。
    private lazy var mosaicThumbnail: CGImage? = makeMosaicThumbnail()

    /// - Parameters:
    ///   - image: 待编辑长图。
    ///   - onComplete: 编辑完成回调（携带合成后的新图）。
    ///   - onCancel: 取消回调（丢弃全部标注）。
    init?(image: NSImage, onComplete: @escaping (NSImage) -> Void, onCancel: @escaping () -> Void) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.sourceCGImage = cg
        self.sourceDisplaySize = image.size
        self.onComplete = onComplete
        self.onCancel = onCancel

        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let width = min(820, visible.width - 48)
        let height = min(680, visible.height - 48)
        // refScale 与实际画布宽（窗口宽 - 左右边距 16 - 图片两侧留白 2）对齐
        let canvasWidth = width - 18
        self.refScale = CGFloat(cg.width) / max(canvasWidth, 1)

        super.init(contentRect: NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2,
                                       width: width, height: height),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        self.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.acceptsMouseMovedEvents = true

        buildUI()
    }

    /// 面板需成为 key 窗口以支持文字输入与快捷键。
    override var canBecomeKey: Bool { true }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        installEscMonitor()
        DiagLog.write("ScrollImageEditorWindow presented: pixels=\(sourceCGImage.width)x\(sourceCGImage.height)")
    }

    override func close() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
        if let tf = activeTextField {
            NotificationCenter.default.removeObserver(
                self, name: NSControl.textDidEndEditingNotification, object: tf)
            activeTextField = nil
        }
        super.close()
    }

    // MARK: - UI 构建

    private func buildUI() {
        let content = EditorContentView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.cornerRadius = 12
        content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.96, alpha: 1).cgColor
        contentView = content

        let w = content.bounds.width
        let h = content.bounds.height
        let toolbarHeight: CGFloat = 44

        // 顶部工具条
        let container = ToolbarContainerView(frame: NSRect(x: 0, y: h - toolbarHeight, width: w, height: toolbarHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(srgbRed: 0.89, green: 0.89, blue: 0.89, alpha: 0.98).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.black.withAlphaComponent(0.06).cgColor
        content.addSubview(container)
        toolbarContainer = container
        buildToolbarButtons(in: container)

        // 画布滚动区（深色衬底衬托图片边界）
        let scrollView = NSScrollView(frame: NSRect(x: 8, y: 8, width: w - 16, height: h - toolbarHeight - 16))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        // 缩放：捏合 / ⌘+滚轮 内置支持，+− 按钮以可见中心为锚点
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8
        content.addSubview(scrollView)
        canvasScrollView = scrollView

        let fitWidth = max(100, scrollView.bounds.width - 2)
        let fitHeight = fitWidth * CGFloat(sourceCGImage.height) / CGFloat(sourceCGImage.width)
        let canvas = EditorCanvasView(frame: NSRect(x: 0, y: 0, width: fitWidth, height: fitHeight))
        canvas.editor = self
        scrollView.documentView = canvas
        canvasView = canvas
    }

    private func buildToolbarButtons(in container: ToolbarContainerView) {
        var x: CGFloat = 10
        let y: CGFloat = 8
        let size: CGFloat = 28

        // 标注工具
        x = addToolButton(container, x: x, y: y, tool: .pen, symbol: "paintbrush", tooltip: "画笔")
        x = addToolButton(container, x: x + 4, y: y, tool: .rectangle, symbol: "square", tooltip: "矩形")
        x = addToolButton(container, x: x + 4, y: y, tool: .ellipse, symbol: "circle", tooltip: "椭圆")
        x = addToolButton(container, x: x + 4, y: y, tool: .arrow, symbol: "arrow.up.right", tooltip: "箭头")
        x = addToolButton(container, x: x + 4, y: y, tool: .text, symbol: "textformat", tooltip: "文字")
        x = addToolButton(container, x: x + 4, y: y, tool: .mosaic, symbol: "square.dashed", tooltip: "马赛克")
        x += 10

        // 颜色（预设色块）
        for (idx, color) in AnnotationColor.presets.enumerated() {
            let btn = NSButton(frame: NSRect(x: x, y: y + 4, width: 20, height: 20))
            btn.title = ""
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 10
            btn.layer?.backgroundColor = nsColor(color).cgColor
            btn.tag = idx
            btn.toolTip = Self.colorName(color)
            btn.target = self
            btn.action = #selector(colorTapped(_:))
            container.addSubview(btn)
            container.registerTooltipButton(btn, text: Self.colorName(color))
            colorButtons.append(btn)
            x += 24
        }
        x += 10

        // 粗细（细/中/粗）
        for (idx, title) in ["细", "中", "粗"].enumerated() {
            let btn = NSButton(frame: NSRect(x: x, y: y, width: 30, height: size))
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
            ])
            btn.title = ""
            btn.tag = idx
            btn.toolTip = "笔画粗细：\(title)"
            btn.target = self
            btn.action = #selector(widthTapped(_:))
            container.addSubview(btn)
            container.registerTooltipButton(btn, text: "笔画粗细：\(title)")
            widthButtons.append(btn)
            x += 32
        }
        x += 10

        // 撤销
        let undo = NSButton(frame: NSRect(x: x, y: y, width: size, height: size))
        undo.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "撤销")
        undo.image?.isTemplate = true
        undo.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        undo.isBordered = false
        undo.wantsLayer = true
        undo.layer?.cornerRadius = 6
        undo.title = ""
        undo.toolTip = "撤销"
        undo.target = self
        undo.action = #selector(undoTapped)
        container.addSubview(undo)
        container.registerTooltipButton(undo, text: "撤销")
        undoButton = undo
        x += size + 10

        // 画布缩放（⌘+滚轮 / 捏合同样可用）
        x = addSmallIconButton(container, x: x, y: y, symbol: "plus.magnifyingglass",
                               tooltip: "放大画布", action: #selector(zoomInTapped))
        x = addSmallIconButton(container, x: x + 4, y: y, symbol: "minus.magnifyingglass",
                               tooltip: "缩小画布", action: #selector(zoomOutTapped))

        // 完成 / 取消（右侧）
        let doneWidth: CGFloat = 56
        let done = NSButton(frame: NSRect(x: container.bounds.width - doneWidth - 10, y: y,
                                          width: doneWidth, height: size))
        done.isBordered = false
        done.wantsLayer = true
        done.layer?.cornerRadius = 6
        done.layer?.backgroundColor = NSColor.systemGreen.cgColor
        done.attributedTitle = NSAttributedString(string: "完成", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ])
        done.title = ""
        done.keyEquivalent = "\r"
        done.toolTip = "完成并应用标注"
        done.target = self
        done.action = #selector(doneTapped)
        container.addSubview(done)
        container.registerTooltipButton(done, text: "完成并应用标注")

        let cancelX = container.bounds.width - doneWidth - 10 - 32
        let cancel = NSButton(frame: NSRect(x: cancelX, y: y, width: 28, height: size))
        cancel.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "取消")
        cancel.image?.isTemplate = true
        cancel.contentTintColor = .white
        cancel.isBordered = false
        cancel.wantsLayer = true
        cancel.layer?.cornerRadius = 6
        cancel.layer?.backgroundColor = NSColor.systemRed.cgColor
        cancel.title = ""
        cancel.toolTip = "取消编辑"
        cancel.target = self
        cancel.action = #selector(cancelTapped)
        container.addSubview(cancel)
        container.registerTooltipButton(cancel, text: "取消编辑")

        selectTool(.pen)
        updateColorSelection()
        updateWidthSelection()
        updateUndoButton()
    }

    @discardableResult
    private func addToolButton(_ container: ToolbarContainerView, x: CGFloat, y: CGFloat,
                               tool: EditorTool, symbol: String, tooltip: String) -> CGFloat {
        let btn = NSButton(frame: NSRect(x: x, y: y, width: 28, height: 28))
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        btn.image?.isTemplate = true
        btn.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.title = ""
        btn.tag = tool.rawValue
        btn.toolTip = tooltip
        btn.target = self
        btn.action = #selector(toolTapped(_:))
        container.addSubview(btn)
        container.registerTooltipButton(btn, text: tooltip)
        toolButtons[tool] = btn
        return x + 28
    }

    @discardableResult
    private func addSmallIconButton(_ container: ToolbarContainerView, x: CGFloat, y: CGFloat,
                                    symbol: String, tooltip: String, action: Selector) -> CGFloat {
        let btn = NSButton(frame: NSRect(x: x, y: y, width: 28, height: 28))
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        btn.image?.isTemplate = true
        btn.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.title = ""
        btn.toolTip = tooltip
        btn.target = self
        btn.action = action
        container.addSubview(btn)
        container.registerTooltipButton(btn, text: tooltip)
        return x + 28
    }

    // MARK: - 工具状态

    private func selectTool(_ tool: EditorTool) {
        currentTool = tool
        for (t, btn) in toolButtons {
            btn.layer?.backgroundColor = (t == tool)
                ? NSColor.black.withAlphaComponent(0.14).cgColor
                : NSColor.black.withAlphaComponent(0.04).cgColor
        }
    }

    private func updateColorSelection() {
        for (idx, btn) in colorButtons.enumerated() {
            let selected = AnnotationColor.presets[idx] == currentColor
            btn.layer?.borderWidth = selected ? 2.5 : 0
            btn.layer?.borderColor = NSColor.systemBlue.cgColor
        }
    }

    private func updateWidthSelection() {
        for (idx, btn) in widthButtons.enumerated() {
            btn.layer?.backgroundColor = (idx == strokeWidthIndex)
                ? NSColor.black.withAlphaComponent(0.14).cgColor
                : NSColor.black.withAlphaComponent(0.04).cgColor
        }
    }

    private func updateUndoButton() {
        undoButton?.isEnabled = !annotations.isEmpty
        undoButton?.contentTintColor = annotations.isEmpty
            ? NSColor.black.withAlphaComponent(0.2)
            : NSColor(calibratedWhite: 0.12, alpha: 1)
    }

    // MARK: - 动作

    @objc private func toolTapped(_ sender: NSButton) {
        guard let tool = EditorTool(rawValue: sender.tag) else { return }
        selectTool(tool)
        DiagLog.write("Editor tool selected: \(tool)")
    }

    @objc private func colorTapped(_ sender: NSButton) {
        let idx = sender.tag
        guard AnnotationColor.presets.indices.contains(idx) else { return }
        currentColor = AnnotationColor.presets[idx]
        updateColorSelection()
        DiagLog.write("Editor color selected: \(Self.colorName(currentColor))")
    }

    @objc private func widthTapped(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < Self.strokeWidths.count else { return }
        strokeWidthIndex = sender.tag
        updateWidthSelection()
        DiagLog.write("Editor stroke width selected: \(Self.strokeWidths[strokeWidthIndex])pt")
    }

    @objc private func undoTapped() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        updateUndoButton()
        canvasView.needsDisplay = true
        DiagLog.write("Editor undo: remaining=\(annotations.count)")
    }

    @objc private func zoomInTapped() {
        zoom(by: 1.25)
    }

    @objc private func zoomOutTapped() {
        zoom(by: 1 / 1.25)
    }

    /// 以可见区域中心为锚点缩放画布。
    private func zoom(by factor: CGFloat) {
        let next = min(canvasScrollView.maxMagnification,
                       max(canvasScrollView.minMagnification, canvasScrollView.magnification * factor))
        let visible = canvasScrollView.contentView.documentVisibleRect
        canvasScrollView.setMagnification(next, centeredAt: NSPoint(x: visible.midX, y: visible.midY))
    }

    @objc private func doneTapped() {
        commitTextEditing()
        let image = renderComposited() ?? NSImage(cgImage: sourceCGImage, size: sourceDisplaySize)
        DiagLog.write("Editor finished: annotations=\(annotations.count) pixels=\(sourceCGImage.width)x\(sourceCGImage.height)")
        let handler = onComplete
        close()
        handler?(image)
    }

    @objc private func cancelTapped() {
        DiagLog.write("Editor cancelled")
        let handler = onCancel
        close()
        handler?()
    }

    // MARK: - 画布事件（EditorCanvasView 转发，坐标已换算为图像像素空间）

    fileprivate func canvasMouseDown(_ view: EditorCanvasView, event: NSEvent) {
        commitTextEditing()
        let viewPoint = view.convert(event.locationInWindow, from: nil)
        let imagePoint = CGPoint(x: viewPoint.x / displayScale, y: viewPoint.y / displayScale)
        let strokePx = Self.strokeWidths[strokeWidthIndex] * refScale
        if currentTool == .text {
            beginTextEditing(at: imagePoint, viewPoint: viewPoint)
        } else if currentTool == .pen {
            drawingAnnotation = EditorAnnotation(type: .pen, points: [imagePoint], text: nil,
                                                 color: currentColor, strokeWidthPx: strokePx, fontSizePx: 0)
        } else {
            drawingAnnotation = EditorAnnotation(type: currentTool, points: [imagePoint, imagePoint], text: nil,
                                                 color: currentColor, strokeWidthPx: strokePx, fontSizePx: 0)
        }
        view.needsDisplay = true
    }

    fileprivate func canvasMouseDragged(_ view: EditorCanvasView, event: NSEvent) {
        guard var d = drawingAnnotation else { return }
        let viewPoint = view.convert(event.locationInWindow, from: nil)
        let imagePoint = CGPoint(x: viewPoint.x / displayScale, y: viewPoint.y / displayScale)
        if d.type == .pen {
            // 距上一采样点超过 3 个显示点才记录，控制路径点数量
            if let last = d.points.last {
                let dx = imagePoint.x - last.x, dy = imagePoint.y - last.y
                let minDist = 3 * refScale
                if dx * dx + dy * dy < minDist * minDist { return }
            }
            d.points.append(imagePoint)
        } else if d.type != .text {
            d.points[d.points.count - 1] = imagePoint
        } else {
            return
        }
        drawingAnnotation = d
        view.needsDisplay = true
    }

    fileprivate func canvasMouseUp(_ view: EditorCanvasView, event: NSEvent) {
        guard var d = drawingAnnotation else { return }
        drawingAnnotation = nil
        if d.type == .pen {
            // 单击画笔：补一个点使点可见
            if d.points.count < 2 {
                d.points.append(CGPoint(x: d.points[0].x + d.strokeWidthPx, y: d.points[0].y))
            }
        } else if d.points.count >= 2 {
            // 矩形/椭圆/箭头/马赛克：忽略无意义的原地单击
            let dx = abs(d.points[1].x - d.points[0].x)
            let dy = abs(d.points[1].y - d.points[0].y)
            if dx < 2 && dy < 2 {
                view.needsDisplay = true
                return
            }
        }
        annotations.append(d)
        updateUndoButton()
        view.needsDisplay = true
        DiagLog.write("Editor annotation added: \(d.type) points=\(d.points.count)")
    }

    // MARK: - 文字标注

    private var hasActiveTextEditing: Bool { activeTextField != nil }

    private func beginTextEditing(at imagePoint: CGPoint, viewPoint: CGPoint) {
        commitTextEditing()
        pendingTextPoint = imagePoint
        let fontSize = Self.fontSizes[strokeWidthIndex]
        let tf = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y, width: 220, height: fontSize + 12))
        tf.font = .systemFont(ofSize: fontSize, weight: .medium)
        tf.placeholderString = "输入文字，回车确认"
        tf.target = self
        tf.action = #selector(textFieldCommitted(_:))
        canvasView.addSubview(tf)
        makeFirstResponder(tf)  // 编辑器自身即窗口（NSWindow 上无 window 属性）
        activeTextField = tf
        // 监听失焦（点击别处）自动提交
        NotificationCenter.default.addObserver(self, selector: #selector(textFieldEnded(_:)),
                                               name: NSControl.textDidEndEditingNotification, object: tf)
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) {
        commitTextEditing()
    }

    // 失焦时自动提交（回车已由 action 提交，guard 防重复）
    @objc private func textFieldEnded(_ notification: Notification) {
        if activeTextField != nil { commitTextEditing() }
    }

    private func commitTextEditing() {
        guard let tf = activeTextField else { return }
        activeTextField = nil  // 先置空，防止 removeFromSuperview 触发 textDidEndEditing 重入
        NotificationCenter.default.removeObserver(
            self, name: NSControl.textDidEndEditingNotification, object: tf)
        let text = tf.stringValue
        tf.removeFromSuperview()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ann = EditorAnnotation(type: .text, points: [pendingTextPoint], text: trimmed,
                                   color: currentColor, strokeWidthPx: 0,
                                   fontSizePx: Self.fontSizes[strokeWidthIndex] * refScale)
        annotations.append(ann)
        updateUndoButton()
        canvasView.needsDisplay = true
        DiagLog.write("Editor text annotation committed: \(trimmed)")
    }

    private func cancelTextEditing() {
        guard let tf = activeTextField else { return }
        activeTextField = nil
        NotificationCenter.default.removeObserver(
            self, name: NSControl.textDidEndEditingNotification, object: tf)
        tf.removeFromSuperview()
        canvasView.needsDisplay = true
        DiagLog.write("Editor text editing cancelled")
    }

    // MARK: - 渲染（画布预览与位图合成共用）

    /// 画布预览：flipped 视图上下文，与合成同一坐标口径。
    /// 先裁剪到脏区，避免长图滚动时全量重绘。
    fileprivate func renderCanvas(_ view: EditorCanvasView, dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bounds = view.bounds
        ctx.clip(to: dirtyRect)
        let scale = bounds.width > 0 ? bounds.width / CGFloat(sourceCGImage.width) : 1

        // flipped 上下文中绘制 CGImage：局部翻转子空间内绘制即正立
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(sourceCGImage, in: CGRect(origin: .zero, size: bounds.size))
        ctx.restoreGState()

        // 标注：进入像素空间绘制（与最终合成同一函数、同一坐标口径）
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        drawAnnotations(annotations, in: ctx)
        if let drawing = drawingAnnotation {
            drawAnnotations([drawing], in: ctx)
        }
        ctx.restoreGState()
    }

    private func drawAnnotations(_ list: [EditorAnnotation], in ctx: CGContext) {
        for ann in list {
            drawOne(ann, in: ctx)
        }
    }

    /// 绘制单个标注。上下文处于图像像素空间（原点左上、y 向下，flipped）。
    private func drawOne(_ ann: EditorAnnotation, in ctx: CGContext) {
        let color = nsColor(ann.color)
        ctx.saveGState()
        switch ann.type {
        case .pen:
            guard ann.points.count >= 2 else { break }
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(ann.strokeWidthPx)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: ann.points[0])
            for i in 1..<ann.points.count {
                ctx.addLine(to: ann.points[i])
            }
            ctx.strokePath()
        case .rectangle:
            guard ann.points.count >= 2 else { break }
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(ann.strokeWidthPx)
            ctx.stroke(normalizedRect(ann.points[0], ann.points[1]))
        case .ellipse:
            guard ann.points.count >= 2 else { break }
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(ann.strokeWidthPx)
            ctx.strokeEllipse(in: normalizedRect(ann.points[0], ann.points[1]))
        case .arrow:
            guard ann.points.count >= 2 else { break }
            let start = ann.points[0], end = ann.points[1]
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(ann.strokeWidthPx)
            ctx.setLineCap(.round)
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()
            drawArrowHead(from: start, to: end, color: color, width: ann.strokeWidthPx, in: ctx)
        case .text:
            guard let text = ann.text, !text.isEmpty, let p = ann.points.first else { break }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: ann.fontSizePx, weight: .medium),
                .foregroundColor: color
            ]
            NSAttributedString(string: text, attributes: attrs).draw(at: p)
        case .mosaic:
            guard ann.points.count >= 2, let thumb = mosaicThumbnail else { break }
            let rect = normalizedRect(ann.points[0], ann.points[1])
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.interpolationQuality = .none
            // 翻转回 bottom-left 像素空间绘制缩略图，无插值放大产生马赛克块
            let ih = CGFloat(sourceCGImage.height)
            ctx.translateBy(x: 0, y: ih)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: CGFloat(sourceCGImage.width), height: ih))
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    private func drawArrowHead(from start: CGPoint, to end: CGPoint, color: NSColor,
                               width: CGFloat, in ctx: CGContext) {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return }
        let angle = atan2(dy, dx)
        // 箭头头部随线宽缩放
        let hl = max(12, width * 3.5), ha: CGFloat = .pi / 6
        let p1 = CGPoint(x: end.x - hl * cos(angle - ha), y: end.y - hl * sin(angle - ha))
        let p2 = CGPoint(x: end.x - hl * cos(angle + ha), y: end.y - hl * sin(angle + ha))
        ctx.setFillColor(color.cgColor)
        ctx.move(to: end)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }

    /// 合成标注到位图：一次性分配整图 RGBA 上下文，完成后即释放。
    /// 无标注时返回 nil（调用方直接使用原图，避免重编码）。
    private func renderComposited() -> NSImage? {
        guard !annotations.isEmpty else { return nil }
        let w = sourceCGImage.width, h = sourceCGImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 转为 top-left 像素坐标（与画布预览同构）
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = nsContext

        // 图像：局部翻转子空间内绘制正立原图
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        ctx.restoreGState()

        drawAnnotations(annotations, in: ctx)
        NSGraphicsContext.current = nil
        guard let composed = ctx.makeImage() else { return nil }
        return NSImage(cgImage: composed, size: sourceDisplaySize)
    }

    /// 马赛克缩略图：整图降采样到宽 64px（保持纵横比），绘制时无插值放大。
    /// 相比逐块读取像素，内存与耗时都大幅降低，视觉效果等同粗粒度马赛克。
    private func makeMosaicThumbnail() -> CGImage? {
        let w = sourceCGImage.width, h = sourceCGImage.height
        guard w > 0, h > 0 else { return nil }
        let thumbW = min(64, max(1, w))
        let thumbH = max(1, Int((CGFloat(h) / CGFloat(w)) * CGFloat(thumbW)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: thumbW, height: thumbH,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: CGFloat(thumbW), height: CGFloat(thumbH)))
        return ctx.makeImage()
    }

    // MARK: - 快捷键

    /// Esc：优先取消文字编辑，否则取消整个编辑器；⌘Z 撤销。
    private func installEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self else { return event }
            if event.keyCode == ScreenshotSession.escKeyCode {
                if self.hasActiveTextEditing {
                    self.cancelTextEditing()
                } else {
                    self.cancelTapped()
                }
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
                self.undoTapped()
                return nil
            }
            return event
        }
    }

    // MARK: - 辅助

    private func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func nsColor(_ color: AnnotationColor) -> NSColor {
        let rgb = color.rgbComponents
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    private static func colorName(_ color: AnnotationColor) -> String {
        switch color {
        case .red: return "红色"
        case .green: return "绿色"
        case .blue: return "蓝色"
        case .purple: return "紫色"
        case .white: return "白色"
        case .black: return "黑色"
        case .custom: return "自定义"
        }
    }
}

/// 编辑器内容背景：卡片风格，背景区域可拖动窗口。
private final class EditorContentView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// 编辑画布：flipped 视图（原点左上），鼠标坐标由编辑器换算为图像像素空间。
/// 画布自身不拖动窗口（拖动交给工具条与背景），绘制事件全部转发给编辑器。
private final class EditorCanvasView: NSView {
    weak var editor: ScrollImageEditorWindow?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        editor?.renderCanvas(self, dirtyRect: dirtyRect)
    }

    override func mouseDown(with event: NSEvent) {
        editor?.canvasMouseDown(self, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        editor?.canvasMouseDragged(self, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        editor?.canvasMouseUp(self, event: event)
    }
}
