import AppKit

/// 放大镜窗口：跟随光标、不接收鼠标（事件穿透到覆盖层），
/// 内容为 ColorMagnifierView（放大网格 + 十字准星 + 色值条）。
final class ColorMagnifierWindow: NSWindow {

    static let magnifierSide: CGFloat = 150
    static let infoBarHeight: CGFloat = 48
    static let windowWidth: CGFloat = 216

    private(set) var magnifierView: ColorMagnifierView!

    init() {
        let size = NSSize(width: ColorMagnifierWindow.windowWidth,
                          height: ColorMagnifierWindow.magnifierSide + ColorMagnifierWindow.infoBarHeight)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        self.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = ColorMagnifierView(frame: NSRect(origin: .zero, size: size))
        self.magnifierView = view
        self.contentView = view
    }

    /// 更新取样结果并跟随光标定位（贴近屏幕右/下边缘时翻转到光标另一侧）。
    func update(location: NSPoint, screen: NSScreen,
                gridColors: [[NSColor?]], cursorColor: NSColor?,
                hexText: String, rgbText: String) {
        magnifierView.update(gridColors: gridColors, cursorColor: cursorColor,
                             hexText: hexText, rgbText: rgbText)
        let size = frame.size
        let gap: CGFloat = 18
        let bounds = screen.frame
        var x = location.x + gap
        var y = location.y - size.height - gap
        if x + size.width > bounds.maxX {
            x = location.x - size.width - gap
        }
        if y < bounds.minY {
            y = location.y + gap
        }
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// 放大镜内容视图：上部放大网格（每个源像素一格，中心格白框即十字准星），
/// 下部色值条（当前色块 + HEX / RGB 文本，数据来自 HexColorFormatter）。
final class ColorMagnifierView: NSView {

    private var gridColors: [[NSColor?]] = []
    private var cursorColor: NSColor?
    private var hexText = ""
    private var rgbText = ""

    override var isFlipped: Bool { true }

    /// 更新数据并重绘（鼠标移动每帧调用，绘制成本 = 网格格数个 fill，微秒级）。
    func update(gridColors: [[NSColor?]], cursorColor: NSColor?,
                hexText: String, rgbText: String) {
        self.gridColors = gridColors
        self.cursorColor = cursorColor
        self.hexText = hexText
        self.rgbText = rgbText
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 背景：深色 HUD + 圆角（与 Toast 风格一致）
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.85).setFill()
        bg.fill()

        // 上部：放大网格区（居中正方形）
        let side = ColorMagnifierWindow.magnifierSide
        let gridOrigin = CGPoint(x: (bounds.width - side) / 2, y: 6)
        let gridRect = NSRect(origin: gridOrigin, size: NSSize(width: side, height: side))
        drawGrid(in: gridRect, context: ctx)

        // 下部：色值条
        let infoRect = NSRect(x: gridRect.minX, y: gridRect.maxY + 4,
                              width: gridRect.width, height: ColorMagnifierWindow.infoBarHeight - 10)
        drawInfoBar(in: infoRect, context: ctx)
    }

    private func drawGrid(in rect: NSRect, context ctx: CGContext) {
        guard !gridColors.isEmpty, !gridColors[0].isEmpty else {
            NSColor.darkGray.setFill()
            ctx.fill(rect)
            return
        }
        let rows = gridColors.count
        let cols = gridColors[0].count
        let cellW = rect.width / CGFloat(cols)
        let cellH = rect.height / CGFloat(rows)
        // 网格圆角裁剪（边缘像素用拉伸显示，见 ColorMagnifierGridMath 夹取语义）
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.clip()
        for (r, row) in gridColors.enumerated() {
            for (c, color) in row.enumerated() {
                let cell = NSRect(x: rect.minX + CGFloat(c) * cellW,
                                  y: rect.minY + CGFloat(r) * cellH,
                                  width: cellW + 0.5, height: cellH + 0.5)
                (color ?? NSColor.darkGray).setFill()
                ctx.fill(cell)
            }
        }
        // 十字准星：中心格白色描边
        let centerRow = rows / 2
        let centerCol = cols / 2
        let centerRect = NSRect(x: rect.minX + CGFloat(centerCol) * cellW,
                                y: rect.minY + CGFloat(centerRow) * cellH,
                                width: cellW, height: cellH)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(Swift.max(1, min(cellW, cellH) * 0.12))
        ctx.stroke(centerRect)
        ctx.restoreGState()
    }

    private func drawInfoBar(in rect: NSRect, context ctx: CGContext) {
        // 左侧当前色块
        let swatch = NSRect(x: rect.minX, y: rect.minY, width: 32, height: rect.height)
        let swatchPath = CGPath(roundedRect: swatch, cornerWidth: 6, cornerHeight: 6, transform: nil)
        (cursorColor ?? NSColor.darkGray).setFill()
        ctx.addPath(swatchPath)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(swatchPath)
        ctx.strokePath()

        // 右侧两行文本：HEX（大）+ RGB（小）
        let textX = swatch.maxX + 10
        let textWidth = rect.maxX - textX
        let hexAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let rgbAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75),
        ]
        (hexText as NSString).draw(in: NSRect(x: textX, y: rect.minY + rect.height * 0.52,
                                              width: textWidth, height: 16), withAttributes: hexAttrs)
        (rgbText as NSString).draw(in: NSRect(x: textX, y: rect.minY + rect.height * 0.12,
                                              width: textWidth, height: 14), withAttributes: rgbAttrs)
    }
}
