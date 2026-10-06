import AppKit

/// 长截图计数文案：滚动控制工具条与实时预览条共用同一格式，保证两处口径一致。
enum ScrollCaptureCounterText {
    static func text(frames: Int, pixelHeight: Int) -> String {
        "已捕获 \(pixelHeight)px · \(frames)帧"
    }
}

/// 长截图实时生长预览条：竖向窄条内自底向上堆叠各帧缩略图。
/// 轻量实现：只持有缩略图、不持有原始帧；追加一帧仅做一次全列表绘制，
/// 无需每次重新拼接（直接 draw 缩略图列表即可）。
/// 宿主窗口由集成者按 `ScrollCaptureToolbar.previewHostFrame` 创建（无框窗口），
/// 本视图作为其 contentView 使用。
public final class LiveStitchPreviewView: NSView {

    /// 单帧记录（轻量：只存缩略图）。
    private struct Item {
        let thumbnail: NSImage
    }

    private var items: [Item] = []
    /// 内部自动累计的计数（append 驱动；setCounter 可显式覆盖，以控制器计数为准）。
    private var frameCount = 0
    private var totalPixelHeight = 0
    /// 整体显示缩放：内容总高超限时压缩，保证全部帧可见。
    private var displayScale: CGFloat = 1
    /// 底部常驻计数文本（绘制在计数带内）。
    private var counterText = ""

    // MARK: 布局常量

    /// 窄条设计宽度（约 72pt，宿主窗口建议同宽）。
    private static let designWidth: CGFloat = 72
    /// 缩略图绘制宽度：窄条减去左右内边距；固定设计宽使缩放计算与宿主窗口尺寸解耦。
    private static let thumbnailWidth: CGFloat = 64
    /// 底部常驻计数带高度。
    private static let counterBandHeight: CGFloat = 20
    /// 背景圆角半径。
    private static let cornerRadius: CGFloat = 10
    /// 内容总高上限：超过 1.6 倍所在屏高时按比例缩小整体显示。
    private static let heightLimitScreenRatio: CGFloat = 1.6

    // MARK: 生命周期

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: 对外 API

    /// 清空全部缩略图与计数，回到初始态。
    public func reset() {
        items.removeAll()
        frameCount = 0
        totalPixelHeight = 0
        displayScale = 1
        counterText = ""
        refreshDisplay()
    }

    /// 追加一帧缩略图（自底向上生长：最早的帧在最下，新帧堆叠在其上方）。
    /// - Parameters:
    ///   - pixelHeight: 该帧对应长图内容的像素高（仅用于内部累计计数）。
    ///   - thumbnail: 该帧缩略图（调用方生成，建议按帧宽等比缩放）。
    public func append(pixelHeight: Int, thumbnail: NSImage) {
        items.append(Item(thumbnail: thumbnail))
        frameCount += 1
        totalPixelHeight += max(0, pixelHeight)
        counterText = ScrollCaptureCounterText.text(frames: frameCount, pixelHeight: totalPixelHeight)
        updateDisplayScale()
        refreshDisplay()
    }

    /// 更新底部计数文字（「已捕获 高度px · N帧」）。
    /// 手动滚动等由控制器统计总数的场景，可显式覆盖内部累计值。
    public func setCounter(frames: Int, pixelHeight: Int) {
        frameCount = frames
        totalPixelHeight = pixelHeight
        counterText = ScrollCaptureCounterText.text(frames: frames, pixelHeight: pixelHeight)
        refreshDisplay()
    }

    /// 期望尺寸：宽 72 窄条；高度为当前内容缩放后总高 + 计数带，
    /// 供宿主窗口参考（宿主也可用 `ScrollCaptureToolbar.previewHostFrame` 直接建窗）。
    public override var intrinsicContentSize: NSSize {
        let screenH = currentScreenHeight()
        let contentH = baseContentHeight() * displayScale
        let height = max(64, min(contentH + Self.counterBandHeight, screenH * Self.heightLimitScreenRatio))
        return NSSize(width: Self.designWidth, height: height)
    }

    // MARK: 绘制

    public override func draw(_ dirtyRect: NSRect) {
        // 深色圆角卡片背景（与滚动控制工具条同色系）
        NSColor(white: 0.16, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()

        // 内容区 = 视图减去底部计数带
        let contentRect = NSRect(x: 0, y: Self.counterBandHeight,
                                 width: bounds.width,
                                 height: max(0, bounds.height - Self.counterBandHeight))

        // 自底向上堆叠：从内容区底部起，按追加顺序（旧 → 新）向上绘制
        let drawW = Self.thumbnailWidth * displayScale
        let drawX = (bounds.width - drawW) / 2
        var y = contentRect.minY
        for item in items {
            let size = item.thumbnail.size
            guard size.width > 0, size.height > 0 else { continue }
            let h = Self.thumbnailWidth * size.height / size.width * displayScale
            item.thumbnail.draw(
                in: NSRect(x: drawX, y: y, width: drawW, height: h),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            y += h
        }

        // 底部常驻计数小字
        guard !counterText.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor(white: 0.75, alpha: 1)
        ]
        let textSize = (counterText as NSString).size(withAttributes: attrs)
        // 分隔线：计数带与内容区之间
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(rect: NSRect(x: 4, y: Self.counterBandHeight - 0.5,
                                  width: max(0, bounds.width - 8), height: 0.5)).fill()
        // 文本居中，超宽时夹在计数带内
        let textX = max(2, (bounds.width - ceil(textSize.width)) / 2)
        let textY = max(2, (Self.counterBandHeight - ceil(textSize.height)) / 2)
        (counterText as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 入窗后所在屏才确定，重算整体缩放（1.6×屏高上限依赖屏高）
        updateDisplayScale()
        refreshDisplay()
    }

    // MARK: 内部

    /// 等比降采样到目标宽度（像素）并包装为 NSImage，供集成方在每帧入库后生成追加缩略图。
    /// CGImage 不可变，本方法线程安全；帧宽不超目标宽度时原样包装（无额外位图内存）。
    public static func downsampledThumbnail(from image: CGImage, targetWidthPx: Int) -> NSImage? {
        guard image.width > 0, targetWidthPx > 0 else { return nil }
        guard image.width > targetWidthPx else {
            return NSImage(cgImage: image,
                           size: NSSize(width: image.width, height: image.height))
        }
        let targetHeight = max(1, Int((CGFloat(image.height) * CGFloat(targetWidthPx) / CGFloat(image.width)).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: targetWidthPx, height: targetHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetWidthPx, height: targetHeight))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: NSSize(width: targetWidthPx, height: targetHeight))
    }

    /// 未缩放的内容总高（点）：各缩略图按固定设计宽等比展开后累加。
    private func baseContentHeight() -> CGFloat {
        var total: CGFloat = 0
        for item in items {
            let size = item.thumbnail.size
            guard size.width > 0, size.height > 0 else { continue }
            total += Self.thumbnailWidth * size.height / size.width
        }
        return total
    }

    /// 重算整体显示缩放：内容总高超过 1.6×所在屏高时按比例缩小；
    /// 同时保证内容在自身内容区内完整可见（宿主窗口可能比 1.6×屏高小）。
    private func updateDisplayScale() {
        let base = baseContentHeight()
        guard base > 0 else {
            displayScale = 1
            return
        }
        let screenH = currentScreenHeight()
        var scale = min(1, screenH * Self.heightLimitScreenRatio / base)
        let boundsContentH = max(24, bounds.height - Self.counterBandHeight)
        scale = min(scale, boundsContentH / base)
        displayScale = scale
    }

    private func currentScreenHeight() -> CGFloat {
        window?.screen?.frame.height ?? NSScreen.main?.frame.height ?? 900
    }

    private func refreshDisplay() {
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }
}
