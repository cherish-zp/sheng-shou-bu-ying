import AppKit
import CoreGraphics
import QuartzCore

/// 截图覆盖层视图：显示捕获的画面 + 半透明遮罩 + 选区框 + 标注绘制。
/// 标准坐标系（isFlipped=false，原点左下），鼠标坐标与 CGContext 一致；
/// 图片直接 ctx.draw 绘制（CGImage 原点左下，标准上下文下正立）。
final class ScreenshotOverlayView: NSView {

    /// 捕获的全屏画面（var：延时截图结束时替换为新鲜帧，其余流程保持不变）。
    var capturedImage: CGImage

    var selectionStart: CGPoint?
    var selectionRect: CGRect?
    let minimumSelection: CGFloat = 10
    /// 自动选区待确认标志：点击自动选区内确认，拖拽则覆盖为手动选区。
    private var pendingConfirm = false

    var isEditMode = false
    let annotations = AnnotationModel()
    var currentTool: AnnotationType?
    var drawingAnnotation: Annotation?
    var currentColor: AnnotationColor = .red
    var strokeWidth: CGFloat = 3

    /// 选区圆角半径（点），默认 16（自动圆角），由工具条「圆角」按钮切换。
    var cornerRadius: CGFloat = CornerRounding.defaultRadius

    // 文字标注编辑状态
    private var activeTextField: NSTextField?
    private var textEditLocalPoint: CGPoint = .zero

    // 选区移动/缩放状态
    private var activeResizeHandle: ResizeHandle?
    private var selectionDragStart: CGPoint = .zero
    private var selectionDragStartRect: CGRect = .zero
    /// 当前光标上下文（用于检测区域切换并触发动效）
    private var currentCursorContext: CursorContext = .background
    /// 选区移动/缩放后回调（用于同步 Coordinator 的 selectionRect）
    var onSelectionChanged: ((CGRect) -> Void)?

    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onAnnotationsChanged: (() -> Void)?

    // MARK: 悬停高亮窗口与重选（单击点选窗口 / 框外重新框选）

    /// mouseDown 前的选区快照：误单击（未命中窗口）时恢复原选区，绝不产生 10×10 坏选区。
    private var preDragSelection: CGRect?
    /// 编辑态点在选区外开启的重选中标志：重选期间走选区阶段的拖拽/单击逻辑。
    private var isReselecting = false
    /// 当前悬停高亮的窗口 rect（nil = 无高亮）。
    private var hoverRect: CGRect?
    /// 上次悬停窗口检测时间（节流，避免 mouseMoved 高频调用 CGWindowList）。
    private var lastHoverCheck: TimeInterval = 0
    /// 悬停窗口检测节流间隔（秒）。
    private let hoverCheckInterval: TimeInterval = 0.08
    /// 由 Coordinator 注入：检测鼠标下最顶层窗口 rect（该屏视图坐标），无可检测窗口时返回 nil。
    var hoverWindowProvider: (() -> CGRect?)?
    /// 重选开始回调（Coordinator 隐藏工具条）。
    var onReselectStarted: (() -> Void)?
    /// 重选取消回调（单击未命中窗口已恢复原选区；Coordinator 恢复工具条显示）。
    var onReselectCancelled: (() -> Void)?
    /// 鼠标活动回调（Coordinator 重置空闲超时，选区未完成时才重新调度）。
    var onMouseActivity: (() -> Void)?

    init(capturedImage: CGImage, frame: NSRect) {
        self.capturedImage = capturedImage
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    /// 允许首次点击直接生效（不激活窗口），避免全屏下首击被吞。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. 绘制捕获的画面（标准上下文，CGImage 原点左下，直接绘制即正立）
        ctx.draw(capturedImage, in: bounds)

       if let sel = selectionRect, isEditMode {
            drawDarkMask(excluding: sel, radius: cornerRadius, in: ctx)
            drawHoverHighlight(in: ctx)
            drawSelectionBorder(sel, radius: cornerRadius, in: ctx)
            // 标注点为相对选区原点的局部坐标，平移上下文至选区原点使其落到正确位置
            // 圆角时裁剪标注，防止超出圆角区域
            clipToRoundedRect(sel, radius: cornerRadius, in: ctx)
            ctx.saveGState()
            ctx.translateBy(x: sel.origin.x, y: sel.origin.y)
            for annotation in annotations.annotations {
                drawSingleAnnotation(annotation, in: ctx)
            }
            if let drawing = drawingAnnotation {
                drawSingleAnnotation(drawing, in: ctx)
            }
            ctx.restoreGState()
            drawResizeHandles(sel, in: ctx)
        } else if let sel = selectionRect {
            drawDarkMask(excluding: sel, radius: cornerRadius, in: ctx)
            drawHoverHighlight(in: ctx)
            drawSelectionBorder(sel, radius: cornerRadius, in: ctx)
            drawSizeLabel(sel)
        } else {
            ctx.setFillColor(NSColor(white: 0, alpha: 0.35).cgColor)
            ctx.fill(bounds)
            drawHoverHighlight(in: ctx)
        }
    }

    /// 绘制悬停窗口高亮：2.5pt systemGreen 描边 + 8% 填充（参考 macOS 原生窗口点选高亮）。
    /// 仅在 hoverRect 有效且 ≠ 当前选区时绘制；编辑态点在选区内时 hoverRect 已被置空，不会走到。
    private func drawHoverHighlight(in ctx: CGContext) {
        guard let hover = hoverRect, hover != selectionRect else { return }
        ctx.setFillColor(NSColor.systemGreen.withAlphaComponent(0.08).cgColor)
        ctx.fill(hover)
        ctx.setStrokeColor(NSColor.systemGreen.cgColor)
        ctx.setLineWidth(2.5)
        ctx.stroke(hover)
    }

    /// 绘制选区边角的 8 个缩放手柄（4 角 + 4 边中点）。
    private func drawResizeHandles(_ rect: CGRect, in ctx: CGContext) {
        let hs: CGFloat = 7
        let positions: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor(calibratedRed: 0.2, green: 0.45, blue: 1.0, alpha: 0.95).cgColor)
        ctx.setLineWidth(1.5)
        for pos in positions {
            let r = CGRect(x: pos.x - hs, y: pos.y - hs, width: hs * 2, height: hs * 2)
            ctx.fillEllipse(in: r)
            ctx.strokeEllipse(in: r)
        }
    }

    /// 将上下文裁剪到圆角矩形（半径 0 时不裁剪）。
    private func clipToRoundedRect(_ rect: CGRect, radius: CGFloat, in ctx: CGContext) {
        let r = CornerRounding.clampedRadius(radius, for: rect.size)
        guard r > 0 else { return }
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.clip()
    }

    private func drawDarkMask(excluding rect: CGRect, radius: CGFloat, in ctx: CGContext) {
        ctx.setFillColor(NSColor(white: 0, alpha: 0.45).cgColor)
        let r = CornerRounding.clampedRadius(radius, for: rect.size)
        ctx.beginPath()
        ctx.addRect(bounds)
        if r > 0 {
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        } else {
            ctx.addRect(rect)
        }
        ctx.fillPath(using: .evenOdd)
    }

    private func drawSelectionBorder(_ rect: CGRect, radius: CGFloat, in ctx: CGContext) {
        ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.9).cgColor)
        ctx.setLineWidth(1)
        let r = CornerRounding.clampedRadius(radius, for: rect.size)
        if r > 0 {
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
            ctx.strokePath()
        } else {
            ctx.stroke(rect)
        }
    }

    private func drawSizeLabel(_ rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
       let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
           .foregroundColor: NSColor.white
       ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let labelRect = CGRect(
            x: min(rect.maxX + 4, bounds.width - size.width - 4),
            y: min(rect.maxY + 4, bounds.height - size.height - 4),
            width: size.width, height: size.height
        )
        let bgRect = labelRect.insetBy(dx: -4, dy: -2)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setFillColor(NSColor(white: 0, alpha: 0.7).cgColor)
        ctx.fill(bgRect)
        str.draw(in: labelRect)
    }

    // MARK: 标注绘制

    private func drawSingleAnnotation(_ annotation: Annotation, in ctx: CGContext) {
        let color = nsColor(annotation.color)
        ctx.saveGState()
        switch annotation.type {
        case .rectangle:
            guard annotation.points.count >= 2 else { break }
            let rect = SelectionRect.normalize(start: annotation.points[0], end: annotation.points[1])
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(annotation.strokeWidth)
            ctx.stroke(rect)
        case .arrow:
            guard annotation.points.count >= 2 else { break }
            let start = annotation.points[0]
            let end = annotation.points[1]
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(annotation.strokeWidth)
            ctx.setLineCap(.round)
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()
            drawArrowHead(from: start, to: end, color: color, in: ctx)
        case .text:
            guard let text = annotation.text, !annotation.points.isEmpty else { break }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: color
            ]
            NSAttributedString(string: text, attributes: attrs).draw(at: annotation.points[0])
        case .mosaic:
            guard annotation.points.count >= 2 else { break }
            let rect = SelectionRect.normalize(start: annotation.points[0], end: annotation.points[1])
            drawMosaic(in: rect, ctx: ctx)
        case .pen:
            guard annotation.points.count >= 2 else { break }
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(annotation.strokeWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: annotation.points[0])
            for i in 1..<annotation.points.count {
                ctx.addLine(to: annotation.points[i])
            }
            ctx.strokePath()
        case .counter:
            guard !annotation.points.isEmpty else { break }
            drawCounterBadge(annotation, color: color, in: ctx)
        }
        ctx.restoreGState()
    }

    /// 绘制序号徽章：主题色实心圆 + 白色序号，圆心为点击点。
    private func drawCounterBadge(_ annotation: Annotation, color: NSColor, in ctx: CGContext) {
        let number = annotation.text ?? "1"
        let badgeRect = CounterBadge.rect(centeredAt: annotation.points[0])
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: badgeRect)
        // 白色序号在圆内居中（文本走 NSGraphicsContext 绘制，与文字标注同一管线）
        let font = NSFont.systemFont(ofSize: CounterBadge.fontSize(forDigits: number.count), weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: number, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(x: badgeRect.midX - size.width / 2,
                             y: badgeRect.midY - size.height / 2 + 1))
    }

    private func drawArrowHead(from start: CGPoint, to end: CGPoint, color: NSColor, in ctx: CGContext) {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return }
        let angle = atan2(dy, dx)
        let hl: CGFloat = 14, ha: CGFloat = .pi / 6
        let p1 = CGPoint(x: end.x - hl * cos(angle - ha), y: end.y - hl * sin(angle - ha))
        let p2 = CGPoint(x: end.x - hl * cos(angle + ha), y: end.y - hl * sin(angle + ha))
        ctx.setFillColor(color.cgColor)
        ctx.move(to: end)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }

    private func drawMosaic(in rect: CGRect, ctx: CGContext) {
        let bs: CGFloat = 8
        let cols = Int(rect.width / bs), rows = Int(rect.height / bs)
        guard let provider = capturedImage.dataProvider, let data = provider.data else { return }
        let bpr = capturedImage.bytesPerRow, bpp = capturedImage.bitsPerPixel / 8
        let ptr = CFDataGetBytePtr(data)
        let iw = capturedImage.width, ih = capturedImage.height
        let viewBounds = bounds
        let sx = iw > 0 ? CGFloat(iw) / viewBounds.width : 1
        let sy = ih > 0 ? CGFloat(ih) / viewBounds.height : 1
        for row in 0..<rows {
            for col in 0..<cols {
                let px = Int((rect.origin.x + CGFloat(col) * bs + bs / 2) * sx)
                let py = Int((rect.origin.y + CGFloat(row) * bs + bs / 2) * sy)
                guard px >= 0, px < iw, py >= 0, py < ih else { continue }
                let off = py * bpr + px * bpp
                guard off + bpp <= CFDataGetLength(data) else { continue }
                ctx.setFillColor(CGColor(red: CGFloat(ptr![off]) / 255, green: CGFloat(ptr![off + 1]) / 255,
                                     blue: CGFloat(ptr![off + 2]) / 255, alpha: 1))
                ctx.fill(CGRect(x: rect.origin.x + CGFloat(col) * bs, y: rect.origin.y + CGFloat(row) * bs,
                                width: bs, height: bs))
            }
        }
    }

    private func nsColor(_ color: AnnotationColor) -> NSColor {
        let rgb = color.rgbComponents
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    // MARK: 鼠标事件（标准坐标系，原点在左下，与 CGContext 一致）

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // 任何鼠标活动都重置空闲超时（由 Coordinator 决定是否重新调度）
        onMouseActivity?()
        if isEditMode { handleEditMouseDown(point); return }
        // 点击瞬间移除悬停高亮，避免与即将开始的新选区混淆
        setHoverRect(nil)
        // 自动选区：点击选区内 -> 待确认；点击选区外 -> 开始新手动选区（快照原选区，误单击时恢复）
        if let sel = selectionRect, sel.contains(point) {
            pendingConfirm = true
            return
        }
        pendingConfirm = false
        preDragSelection = selectionRect
        selectionStart = point
        selectionRect = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isEditMode { handleEditMouseDrag(point); return }
        // 拖拽也算鼠标活动（重置空闲超时）
        onMouseActivity?()
        // 待确认状态下拖拽 -> 转为手动选区
        if pendingConfirm {
            pendingConfirm = false
            preDragSelection = nil
            selectionStart = point
            selectionRect = CGRect(origin: point, size: .zero)
        }
        guard let start = selectionStart else { return }
        var rect = SelectionRect.normalize(start: start, end: point)
        rect = SelectionRect.clamp(rect, to: bounds)
        selectionRect = rect
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isEditMode { handleEditMouseUp(point); return }
        // 自动选区：点击选区内确认（既有路径不变）
        if pendingConfirm {
            pendingConfirm = false
            if let sel = selectionRect { onSelectionComplete?(sel) }
            return
        }
        guard let start = selectionStart else { return }
        // 单击（非拖拽）：点选窗口，或恢复 mouseDown 前的选区——绝不把 0×0 强制成 10×10 坏选区
        if SelectionClickResolver.isClick(start: start, end: point) {
            let windowRect = hoverWindowProvider?()
            switch SelectionClickResolver.resolve(clickPoint: point, selection: preDragSelection, windowRect: windowRect) {
            case .confirmSelection:
                // 理论不达（选区内点击在 mouseDown 已转 pendingConfirm）；兜底恢复快照
                finishReselectCancelled()
            case .selectWindow(let rect):
                DiagLog.write("Click selected window: \(rect)")
                selectionRect = rect
                setHoverRect(nil)
                isReselecting = false
                selectionStart = nil
                preDragSelection = nil
                needsDisplay = true
                onSelectionComplete?(rect)
            case .ignore:
                finishReselectCancelled()
            }
            return
        }
        // 真拖拽：规范化 + 夹取 + 最小尺寸约束后完成（维持既有行为）
        guard var rect = selectionRect else { return }
        rect = SelectionRect.enforceMinimumSize(rect, minimum: minimumSelection)
        if !SelectionRect.isValid(rect, minimum: minimumSelection) {
            onCancel?()
            return
        }
        selectionRect = rect
        selectionStart = nil
        preDragSelection = nil
        needsDisplay = true
        onSelectionComplete?(rect)
    }

    /// 重选取消（含选区阶段误单击兜底）：恢复 mouseDown 前的选区快照；
    /// 重选中（编辑态框外点击进入）时回到编辑态并通知 Coordinator 恢复工具条。
    private func finishReselectCancelled() {
        selectionRect = preDragSelection
        preDragSelection = nil
        selectionStart = nil
        setHoverRect(nil)
        if isReselecting {
            isReselecting = false
            isEditMode = true
            NSCursor.crosshair.set()
            onReselectCancelled?()
        }
        needsDisplay = true
        DiagLog.write("Click ignored: restored selection \(String(describing: selectionRect))")
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // 统一入口：任何鼠标活动都重置空闲超时（由 Coordinator 决定是否重新调度）
        onMouseActivity?()
        if isEditMode {
            guard activeResizeHandle == nil else { return }
            if currentTool == nil, let sel = selectionRect {
                let handle = SelectionRect.hitTest(point: point, in: sel, handleSize: 8)
                updateCursor(for: handle)
                transitionCursor(to: .screenshotArea, at: point)
            } else {
                NSCursor.crosshair.set()
                transitionCursor(to: .screenshotArea, at: point)
            }
            updateHoverHighlight(at: point)
        } else {
            // 选区阶段（初始选区/重选中）：光标固定十字，允许悬停高亮窗口
            NSCursor.crosshair.set()
            transitionCursor(to: .screenshotArea, at: point)
            updateHoverHighlight(at: point)
        }
    }

    // MARK: 悬停高亮

    /// 悬停高亮是否可用：无拖拽进行中、无标注工具、非待确认，
    /// 且（选区阶段 || 编辑态光标模式且点在选区及其手柄热区之外）。
    private func hoverActive(at point: CGPoint) -> Bool {
        guard hoverWindowProvider != nil else { return false }
        guard activeResizeHandle == nil, drawingAnnotation == nil, !pendingConfirm else { return false }
        if isEditMode {
            guard currentTool == nil, let sel = selectionRect else { return false }
            // 点在选区或手柄热区上时不高亮（用户在操作自家选区）
            return SelectionRect.hitTest(point: point, in: sel, handleSize: 8) == nil
        }
        return true
    }

    /// 按节流间隔检测鼠标下窗口并更新悬停高亮；条件不满足时立即清除。
    private func updateHoverHighlight(at point: CGPoint) {
        guard hoverActive(at: point) else {
            setHoverRect(nil)
            return
        }
        let now = CACurrentMediaTime()
        guard now - lastHoverCheck >= hoverCheckInterval else { return }
        lastHoverCheck = now
        let windowRect = hoverWindowProvider?()
        // 与当前选区相同的窗口不高亮（画了也看不见）
        let newHover: CGRect? = (windowRect != nil && windowRect != selectionRect) ? windowRect : nil
        setHoverRect(newHover)
    }

    /// 更新悬停高亮 rect，按新旧 rect 并集局部失效重绘（避免残影）。
    private func setHoverRect(_ rect: CGRect?) {
        guard rect != hoverRect else { return }
        if let old = hoverRect {
            setNeedsDisplay(old.insetBy(dx: -3, dy: -3))
        }
        hoverRect = rect
        if let new = rect {
            setNeedsDisplay(new.insetBy(dx: -3, dy: -3))
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        transitionCursor(to: .screenshotArea, at: point)
    }

    override func mouseExited(with event: NSEvent) {
        // 拖拽中不切换光标（避免缩放/移动时光标闪变）
        guard activeResizeHandle == nil, drawingAnnotation == nil else { return }
        // 鼠标离开覆盖层（如移到工具条/其他屏）时清除悬停高亮
        setHoverRect(nil)
        let point = convert(event.locationInWindow, from: nil)
        transitionCursor(to: .toolbarArea, at: point)
        NSCursor.arrow.set()
    }

    /// 光标上下文切换：区域变化时设置新光标并显示涟漪动效。
    private func transitionCursor(to context: CursorContext, at point: CGPoint) {
        if CursorContext.shouldAnimate(from: currentCursorContext, to: context) {
            showCursorRipple(at: point, style: context.defaultStyle)
        }
        currentCursorContext = context
    }

    /// 在鼠标位置显示涟漪扩散动效（光标切换视觉反馈）。
    private func showCursorRipple(at point: CGPoint, style: CursorStyle) {
        let startSize: CGFloat = 24
        let ripple = NSView(frame: NSRect(x: point.x - startSize / 2, y: point.y - startSize / 2,
                                          width: startSize, height: startSize))
        ripple.wantsLayer = true
        ripple.layer?.cornerRadius = startSize / 2
        ripple.layer?.borderWidth = 2
        ripple.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        ripple.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(ripple)

        let endSize: CGFloat = 44
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ripple.animator().frame = NSRect(x: point.x - endSize / 2, y: point.y - endSize / 2,
                                             width: endSize, height: endSize)
            ripple.animator().alphaValue = 0
        }, completionHandler: {
            ripple.removeFromSuperview()
        })
    }

    /// 根据命中的手柄设置对应的光标。
    private func updateCursor(for handle: ResizeHandle?) {
        let kind: ResizeCursorKind = handle?.cursorKind ?? .crosshair
        ResizeCursorFactory.cursor(for: kind).set()
    }

    // MARK: 编辑模式

    private func handleEditMouseDown(_ point: CGPoint) {
        DiagLog.write("handleEditMouseDown: point=\(point) tool=\(String(describing: currentTool)) hasSel=\(selectionRect != nil)")
        // 光标模式（未选标注工具）：检测选区移动/缩放手柄
        if currentTool == nil, let sel = selectionRect {
           if let handle = SelectionRect.hitTest(point: point, in: sel, handleSize: 8) {
               activeResizeHandle = handle
               selectionDragStart = point
               selectionDragStartRect = sel
                // 拖拽时光标保持缩放样式；内部拖拽用闭合抓手
                if handle == .interior {
                    NSCursor.closedHand.set()
                } else {
                    ResizeCursorFactory.cursor(for: handle.cursorKind).set()
                }
                return
            }
            // 点在选区外（未命中手柄）：开启重选——转入选区阶段，重新框选或点选窗口
            beginReselecting(at: point)
            return
        }
        guard let tool = currentTool, let sel = selectionRect else { return }
        let local = CGPoint(x: point.x - sel.origin.x, y: point.y - sel.origin.y)
        if tool == .text {
            startTextEditing(at: point, localPoint: local)
        } else if tool == .counter {
            // 序号标注：单击放置（自动递增），无拖拽语义
            annotations.addCounter(at: local, color: currentColor)
            onAnnotationsChanged?()
            needsDisplay = true
        } else if tool == .pen {
            drawingAnnotation = Annotation(type: .pen, points: [local], color: currentColor, strokeWidth: strokeWidth)
        } else {
            drawingAnnotation = Annotation(type: tool, points: [local, local], color: currentColor, strokeWidth: strokeWidth)
        }
        needsDisplay = true
    }

    private func handleEditMouseDrag(_ point: CGPoint) {
        // 选区移动/缩放
        if let handle = activeResizeHandle {
            // 拖拽中保持光标样式不变
            if handle == .interior { NSCursor.closedHand.set() }
            else { ResizeCursorFactory.cursor(for: handle.cursorKind).set() }
            let delta = CGVector(dx: point.x - selectionDragStart.x, dy: point.y - selectionDragStart.y)
            if handle == .interior {
                selectionRect = SelectionRect.move(selectionDragStartRect, by: delta, bounds: bounds)
            } else {
                selectionRect = SelectionRect.resize(selectionDragStartRect, handle: handle,
                                                     delta: delta, minSize: minimumSelection, bounds: bounds)
            }
            if let rect = selectionRect { onSelectionChanged?(rect) }
            needsDisplay = true
            return
        }
        guard let sel = selectionRect else { return }
        let local = CGPoint(x: point.x - sel.origin.x, y: point.y - sel.origin.y)
        guard var d = drawingAnnotation, d.type != .text else { return }
        if d.type == .pen {
            PenPathBuilder.append(local, to: &d.points)
        } else {
            d.points[d.points.count - 1] = local
        }
        drawingAnnotation = d
        needsDisplay = true
    }

    private func handleEditMouseUp(_ point: CGPoint) {
        if activeResizeHandle != nil {
            let wasInterior = activeResizeHandle == .interior
            activeResizeHandle = nil
            // 释放后恢复悬停光标
            NSCursor.crosshair.set()
            if wasInterior { NSCursor.openHand.set() }
            return
        }
        guard let d = drawingAnnotation else { return }
        annotations.add(d)
        drawingAnnotation = nil
        onAnnotationsChanged?()
        needsDisplay = true
    }

    /// 开始重选：退出编辑态转入选区阶段（复用选区阶段的拖拽/单击逻辑），
    /// 快照当前选区以便误单击取消时恢复；此后 mouseUp 的单击/拖拽分流按选区阶段处理。
    /// 注意：重选中 isEditMode 已为 false，handleEditMouseDrag/handleEditMouseUp 天然不再进入。
    private func beginReselecting(at point: CGPoint) {
        isReselecting = true
        preDragSelection = selectionRect
        isEditMode = false
        pendingConfirm = false
        selectionStart = point
        selectionRect = CGRect(origin: point, size: .zero)
        setHoverRect(nil)
        NSCursor.crosshair.set()
        needsDisplay = true
        onReselectStarted?()
        DiagLog.write("Reselect started: preDrag=\(String(describing: preDragSelection))")
    }

    // MARK: 文字标注编辑

    /// 在点击位置弹出文本输入框，用户输入文字后回车提交。
    private func startTextEditing(at viewPoint: CGPoint, localPoint: CGPoint) {
        // 先提交正在编辑的文字（如有），再开始新的输入
        if activeTextField != nil { commitTextEditing() }
        textEditLocalPoint = localPoint
        let tf = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y, width: 220, height: 28))
        tf.font = .systemFont(ofSize: 16, weight: .medium)
        tf.placeholderString = "输入文字，回车确认"
        tf.target = self
        tf.action = #selector(textFieldCommitted(_:))
        tf.delegate = nil
        tf.stringValue = ""
        addSubview(tf)
        window?.makeFirstResponder(tf)
        activeTextField = tf
        // 监听失焦（点击别处）自动提交
        NotificationCenter.default.addObserver(self, selector: #selector(textFieldEndedEditing(_:)),
                                               name: NSControl.textDidEndEditingNotification, object: tf)
        DiagLog.write("startTextEditing at local=\(localPoint)")
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) {
        commitTextEditing()
    }

    private func commitTextEditing() {
        guard let tf = activeTextField else { return }
        activeTextField = nil  // 先置空，防止 removeFromSuperview 触发 controlTextDidEndEditing 重入
        NotificationCenter.default.removeObserver(self, name: NSControl.textDidEndEditingNotification, object: tf)
        let text = tf.stringValue
        if let ann = AnnotationModel.textAnnotation(at: textEditLocalPoint, text: text, color: currentColor) {
            annotations.add(ann)
            onAnnotationsChanged?()
            DiagLog.write("Text annotation committed: \(text)")
        }
        tf.removeFromSuperview()
        needsDisplay = true
    }

    private func cancelTextEditing() {
        if let tf = activeTextField {
            NotificationCenter.default.removeObserver(self, name: NSControl.textDidEndEditingNotification, object: tf)
        }
        activeTextField?.removeFromSuperview()
        activeTextField = nil
        needsDisplay = true
        DiagLog.write("Text editing cancelled")
    }

    /// ESC 优先取消文字编辑；返回 true 表示已处理（不应再取消截图）。
    func cancelTextEditingIfActive() -> Bool {
        if activeTextField != nil {
            cancelTextEditing()
            return true
        }
        return false
    }

    // 失焦时自动提交（回车已由 action 提交，guard 防重复）
    @objc private func textFieldEndedEditing(_ notification: Notification) {
        if activeTextField != nil { commitTextEditing() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == ScreenshotSession.escKeyCode {
            if activeTextField != nil { cancelTextEditing() } else { onCancel?() }
        }
        else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            annotations.undo(); onAnnotationsChanged?(); needsDisplay = true
        }
    }
}

extension ScreenshotOverlayView {
    func drawAnnotationPublic(_ annotation: Annotation, in ctx: CGContext) {
        drawSingleAnnotation(annotation, in: ctx)
    }
}
