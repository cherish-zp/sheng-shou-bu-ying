import AppKit

/// 拼接结果窗代理：结果窗按钮事件回调。
/// 面板自身不关闭、不释放——所有出口（含关闭）都只回调，
/// 由集成方（协调器）决定后续（如保存后关窗、编辑后切换到标注工具条）。
public protocol ScrollResultPanelDelegate: AnyObject {
    /// 保存到磁盘（~/Pictures/Screenshots）。
    func resultPanelDidSave(_ panel: ScrollResultPanel)
    /// 复制到剪贴板。
    func resultPanelDidCopy(_ panel: ScrollResultPanel)
    /// 贴图到桌面。
    func resultPanelDidPin(_ panel: ScrollResultPanel)
    /// 进入标注编辑。
    func resultPanelDidEdit(_ panel: ScrollResultPanel)
    /// 强制堆叠重拼（忽略重叠检测，逐帧堆叠）。
    func resultPanelDidRetryForced(_ panel: ScrollResultPanel)
    /// 关闭结果窗。
    func resultPanelDidClose(_ panel: ScrollResultPanel)
}

/// 拼接结果视图数据：拼接质量提示的展示模型（issue → 中文文案的映射写在本文件内）。
/// 并行线的 ScrollStitchIssue / ScrollStitchFailure 由集成方解包为
/// 基础类型（Int 可选元组）后经 `make` / `makeFailure` 桥接，本文件不引用其类型。
public struct ScrollResultIssueViewData {

    public enum Kind {
        /// 未检测到可靠重叠（按固定步进堆叠）。
        case noReliableOverlap
        /// 重复纹理（列表/网格等）导致匹配歧义。
        case ambiguousPattern
        /// 选区含固定带（吸顶导航等），已排除其干扰。
        case fixedBandExcluded
        /// 接缝不可靠，按上一段滚动量外推。
        case extrapolatedBoundary
        /// 接缝无法对齐，该段边界已丢弃。
        case droppedBoundary
        /// 已强制堆叠（集成方触发强制重拼后提示；无位置细节）。
        case forcedStack
        /// 达到内存上限自动结束（集成方注入的整体性提示）。
        case budgetReached
        /// 自动滚动到底自动结束（集成方注入的整体性提示）。
        case autoBottom
    }

    public let kind: Kind
    /// 位置细节，如「第 3 段」「固定带 60px」。
    public let detail: String

    public init(kind: Kind, detail: String) {
        self.kind = kind
        self.detail = detail
    }

    /// 单条展示文案（不做同类聚合；多条场景请用 `displayTexts(for:)`）。
    public var displayText: String {
        ScrollResultIssueViewData.displayTexts(for: [self]).first ?? ""
    }

    // MARK: 桥接工厂（基础类型参数，供集成方从拼接契约类型转换）

    /// 由 ScrollStitchIssue 桥接：集成方解包 case 关联值后传入基础类型。
    /// - Parameters:
    ///   - kind: 对应 ScrollStitchIssue 的 case（noReliableOverlap(frameIndex:)/
    ///           ambiguousPattern(frameIndex:)/fixedBandExcluded(height:)）。
    ///   - frameIndex: 0 起始的帧序号（展示为「第 frameIndex+1 段」）。
    ///   - bandHeight: 固定带像素高（仅 fixedBandExcluded 使用，展示为「固定带 Hpx」）。
    public static func make(kind: Kind, frameIndex: Int? = nil, bandHeight: Int? = nil) -> ScrollResultIssueViewData {
        switch kind {
        case .fixedBandExcluded:
            return ScrollResultIssueViewData(kind: kind, detail: bandHeight.map { "固定带 \($0)px" } ?? "固定区域")
        case .noReliableOverlap, .ambiguousPattern, .extrapolatedBoundary, .droppedBoundary:
            return ScrollResultIssueViewData(kind: kind, detail: frameIndex.map { "第 \($0 + 1) 段" } ?? "该段")
        case .forcedStack, .budgetReached, .autoBottom:
            // 整体性提示无位置细节，文案由 displayTexts 固定输出
            return ScrollResultIssueViewData(kind: kind, detail: "")
        }
    }

    /// 由 ScrollStitchFailure 桥接：`extrapolated` 为 true 表示外推（extrapolated），
    /// false 表示丢弃（dropped）。`usedOffset`（实际使用的滚动量 px）目前不进入文案，
    /// 保留参数以对齐契约；如需展示可扩展对应文案。
    public static func makeFailure(frameIndex: Int, extrapolated: Bool, usedOffset: Int) -> ScrollResultIssueViewData {
        _ = usedOffset
        let detail = "第 \(frameIndex + 1) 段"
        return ScrollResultIssueViewData(kind: extrapolated ? .extrapolatedBoundary : .droppedBoundary,
                                         detail: detail)
    }

    /// 批量桥接：集成方把 [ScrollStitchIssue] 解包为 (kind, frameIndex, bandHeight) 元组数组后调用。
    public static func makeBatch(_ raw: [(kind: Kind, frameIndex: Int?, bandHeight: Int?)]) -> [ScrollResultIssueViewData] {
        raw.map { make(kind: $0.kind, frameIndex: $0.frameIndex, bandHeight: $0.bandHeight) }
    }

    // MARK: issue → 中文文案映射（语义准确、不吓唬用户）

    /// 生成结果窗 issues 区的展示文案：同类多条聚合计数（「检测到 N 处…」），
    /// 单条时携带位置细节（「第 3 段…」）。顺序与严重程度相关：固定带 → 重叠缺失 → 歧义 → 外推 → 丢弃。
    public static func displayTexts(for issues: [ScrollResultIssueViewData]) -> [String] {
        var texts: [String] = []

        // 整体性提示（集成方注入）：强制堆叠 / 内存上限 / 自动到底，各恒为单条
        for item in issues where item.kind == .forcedStack {
            texts.append("已强制堆叠：未做重叠检测，内容可能重复")
        }
        for item in issues where item.kind == .budgetReached {
            texts.append("已达内存上限，自动结束")
        }
        for item in issues where item.kind == .autoBottom {
            texts.append("已滚动到底部，自动结束")
        }

        // 固定带：恒为单条（高度信息唯一）
        for item in issues where item.kind == .fixedBandExcluded {
            texts.append("选区含固定区域（\(item.detail)），已自动排除其干扰，拼接精度可能略受影响")
        }

        func aggregate(_ kind: Kind, single: (String) -> String, plural: (Int) -> String) {
            let items = issues.filter { $0.kind == kind }
            guard !items.isEmpty else { return }
            if items.count == 1 {
                texts.append(single(items[0].detail))
            } else {
                texts.append(plural(items.count))
            }
        }

        aggregate(.noReliableOverlap,
                  single: { "\($0)与上一段未检测到可靠重叠，已按固定步进堆叠，接缝处可能重复或缺失" },
                  plural: { "检测到 \($0) 处接缝无可靠重叠，已按固定步进堆叠，接缝处可能重复或缺失" })

        aggregate(.ambiguousPattern,
                  single: { "\($0)位于重复纹理区域（如列表/网格），拼接位置可能有轻微偏差，建议检查接缝" },
                  plural: { "检测到 \($0) 处重复纹理（如列表/网格），拼接位置可能有轻微偏差，建议检查接缝" })

        aggregate(.extrapolatedBoundary,
                  single: { "\($0)接缝不可靠，已按上一段滚动量外推，可能存在错位" },
                  plural: { "检测到 \($0) 处接缝不可靠，已按上一段滚动量外推，可能存在错位" })

        aggregate(.droppedBoundary,
                  single: { "\($0)接缝无法对齐，已丢弃该段边界，内容可能不连续" },
                  plural: { "检测到 \($0) 处接缝无法对齐，已丢弃，内容可能不连续" })

        return texts
    }
}

/// 拼接结果窗：长截图完成后的统一出口（保存/复制/贴图/编辑/强制重拼/关闭）。
/// 替代旧滚动工具条上被误当「保存」的复制按钮——所有出口集中于此，
/// 滚动工具条上只保留滚动控制。
/// 窗口风格对齐项目现有面板：无边框非激活面板（不抢 key）、深色圆角卡片、
/// level 高于截图覆盖层；显示在鼠标所在屏的居中偏下位置（见 positionPanel）。
public final class ScrollResultPanel: NSPanel {

    private weak var panelDelegate: ScrollResultPanelDelegate?

    // MARK: 布局常量

    private static let contentWidth: CGFloat = 364
    private static let edgePadding: CGFloat = 14
    private static let buttonSize: CGFloat = 28
    /// 预览视口高度上下限。
    private static let minPreviewHeight: CGFloat = 140
    private static let minViewportFloor: CGFloat = 120

    // MARK: 生命周期

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // 与子面板同层级：高于截图覆盖层(screenSaver)；展示时覆盖层已收起
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = false
        acceptsMouseMovedEvents = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: 对外 API

    /// 展示拼接结果（重复调用会重建内容并重新定位，支持「强制重拼」后原窗刷新）。
    public func show(image: NSImage,
                     issues: [ScrollResultIssueViewData],
                     canRetryForced: Bool,
                     delegate: ScrollResultPanelDelegate?) {
        panelDelegate = delegate
        rebuildContent(image: image, issues: issues, canRetryForced: canRetryForced)
        positionPanel()
        orderFrontRegardless()
        DiagLog.write("ScrollResultPanel shown: size=\(image.size) issues=\(issues.count) canRetryForced=\(canRetryForced)")
    }

    // MARK: 尺寸度量

    /// 布局度量：面板尺寸、预览视口高、issues 区高。构建与测高共用，避免两处公式漂移。
    private static func metrics(image: NSImage, issues: [ScrollResultIssueViewData])
        -> (size: NSSize, viewportHeight: CGFloat, issuesHeight: CGFloat) {
        let previewWidth = contentWidth - edgePadding * 2
        let imageSize = image.size
        // 图片按预览宽度等比展开后的完整高度（超出视口则在滚动区内滚动）
        let fitHeight = imageSize.width > 0 ? previewWidth * imageSize.height / imageSize.width : 200
        let screenH = NSScreen.main?.visibleFrame.height ?? 900
        let maxViewport = max(minPreviewHeight, screenH * 0.45)
        var viewport = min(max(fitHeight, minPreviewHeight), maxViewport)

        let texts = ScrollResultIssueViewData.displayTexts(for: issues)
        let issuesHeight: CGFloat = texts.isEmpty ? 0 : CGFloat(texts.count) * 16 + 6
        let titleHeight: CGFloat = 20
        let buttonRowHeight: CGFloat = 28

        var total = 12 + titleHeight + 8 + issuesHeight + 8 + viewport + 10 + buttonRowHeight + 12
        // 总高超出屏高 85% 时压缩预览视口（下限 minViewportFloor）
        let maxTotal = max(280, screenH * 0.85)
        if total > maxTotal {
            viewport = max(minViewportFloor, viewport - (total - maxTotal))
            total = 12 + titleHeight + 8 + issuesHeight + 8 + viewport + 10 + buttonRowHeight + 12
        }
        return (NSSize(width: contentWidth, height: total), viewport, issuesHeight)
    }

    /// 位图尺寸文案（优先取像素，NSImage.size 是显示点尺寸）。
    private static func pixelSizeText(of image: NSImage) -> String {
        if let rep = image.representations.first {
            return "\(rep.pixelsWide)×\(rep.pixelsHigh) px"
        }
        return "\(Int(image.size.width.rounded()))×\(Int(image.size.height.rounded())) px"
    }

    // MARK: 构建内容

    private func rebuildContent(image: NSImage, issues: [ScrollResultIssueViewData], canRetryForced: Bool) {
        container?.removeFromSuperview()

        let metrics = Self.metrics(image: image, issues: issues)
        let size = metrics.size
        setContentSize(size)

        // 复用主工具条的内容容器：强制箭头光标 + 自绘悬停提示（同一套样式语言）
        let c = ToolbarContainerView(frame: NSRect(origin: .zero, size: size))
        c.wantsLayer = true
        c.autoresizingMask = [.width, .height]
        c.layer?.cornerRadius = 12
        c.layer?.masksToBounds = true
        // 深色圆角卡片：与滚动控制工具条同色系
        c.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.98).cgColor
        c.layer?.borderWidth = 1
        c.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        contentView = c
        container = c

        var y = size.height - 12

        // 标题行：左标题 + 右侧位图尺寸
        let title = NSTextField(labelWithString: "长截图结果")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        title.frame = NSRect(x: Self.edgePadding, y: y - 18, width: 140, height: 18)
        c.addSubview(title)

        let sizeLabel = NSTextField(labelWithString: Self.pixelSizeText(of: image))
        sizeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = NSColor(white: 0.7, alpha: 1)
        sizeLabel.alignment = .right
        sizeLabel.frame = NSRect(x: size.width - Self.edgePadding - 160, y: y - 16, width: 160, height: 14)
        c.addSubview(sizeLabel)
        y -= 20 + 8

        // issues 区：每条一行黄色小字警示（常驻可见，不随图片滚动）
        let texts = ScrollResultIssueViewData.displayTexts(for: issues)
        for text in texts {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .systemYellow
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: Self.edgePadding, y: y - 14,
                                 width: size.width - Self.edgePadding * 2, height: 14)
            c.addSubview(label)
            y -= 16
        }
        if !texts.isEmpty { y -= 6 }

        // 预览长图：宽度适配，超高可滚动（documentView 高 = max(视口, 完整展开高)）
        let previewWidth = Self.contentWidth - Self.edgePadding * 2
        let imageSize = image.size
        let fitHeight = imageSize.width > 0 ? previewWidth * imageSize.height / imageSize.width : 200
        let viewportHeight = metrics.viewportHeight
        let docHeight = max(viewportHeight, fitHeight)

        let scrollView = NSScrollView(frame: NSRect(x: Self.edgePadding, y: 12 + Self.buttonSize + 10,
                                                    width: previewWidth, height: viewportHeight))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: previewWidth, height: docHeight))
        let imageView = NSImageView(frame: NSRect(x: 0, y: docHeight - fitHeight,
                                                  width: previewWidth, height: fitHeight))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        docView.addSubview(imageView)
        scrollView.documentView = docView
        c.addSubview(scrollView)

        // 底部按钮行：保存 / 复制 / 贴图 / 编辑 / [强制堆叠] / 关闭（靠右）
        let buttonY: CGFloat = 12
        var x = Self.edgePadding
        x = addResultButton(in: c, x: x, y: buttonY, symbol: "arrow.down", bgColor: .systemGreen,
                            tooltip: "保存到 ~/Pictures/Screenshots", action: #selector(saveTapped)) + 4
        x = addResultButton(in: c, x: x, y: buttonY, symbol: "doc.on.doc", bgColor: .systemBlue,
                            tooltip: "复制到剪贴板", action: #selector(copyTapped)) + 4
        x = addResultButton(in: c, x: x, y: buttonY, symbol: "pin.fill", bgColor: .systemOrange,
                            tooltip: "贴图到桌面", action: #selector(pinTapped)) + 4
        x = addResultButton(in: c, x: x, y: buttonY, symbol: "pencil.and.outline", bgColor: .systemPurple,
                            tooltip: "进入标注编辑", action: #selector(editTapped)) + 4
        if canRetryForced {
            x = addResultButton(in: c, x: x, y: buttonY, symbol: "arrow.down.to.line",
                                bgColor: NSColor(white: 0.45, alpha: 1),
                                tooltip: "忽略重叠检测，逐帧堆叠（内容可能重复）",
                                action: #selector(retryForcedTapped)) + 4
        }
        let close = NSButton(frame: NSRect(x: size.width - Self.edgePadding - Self.buttonSize,
                                           y: buttonY, width: Self.buttonSize, height: Self.buttonSize))
        configureResultButton(close, symbol: "xmark", bgColor: .systemRed, tooltip: "关闭")
        close.target = self
        close.action = #selector(closeTapped)
        c.addSubview(close)
        c.registerTooltipButton(close, text: "关闭")
    }

    /// 结果窗图标按钮：复刻主工具条 addIconButton 视觉（28pt 无边框 + 圆角 6 + 彩色底 + 白色模板图）。
    @discardableResult
    private func addResultButton(in container: NSView, x: CGFloat, y: CGFloat,
                                 symbol: String, bgColor: NSColor,
                                 tooltip: String, action: Selector) -> CGFloat {
        let btn = NSButton(frame: NSRect(x: x, y: y, width: Self.buttonSize, height: Self.buttonSize))
        configureResultButton(btn, symbol: symbol, bgColor: bgColor, tooltip: tooltip)
        btn.target = self
        btn.action = action
        container.addSubview(btn)
        (container as? ToolbarContainerView)?.registerTooltipButton(btn, text: tooltip)
        return x + Self.buttonSize
    }

    private func configureResultButton(_ btn: NSButton, symbol: String, bgColor: NSColor, tooltip: String) {
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        btn.image?.isTemplate = true
        btn.contentTintColor = .white
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.layer?.backgroundColor = bgColor.cgColor
        btn.toolTip = tooltip
    }

    /// 定位：鼠标所在屏（兜底主屏）可视区内水平居中、垂直略低于居中（居中偏下）。
    /// 长图预览窗偏下放置更贴近底部按钮操作热区，且不遮挡屏幕上半部分的浏览内容。
    private func positionPanel() {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = frame.size
        var x = visible.midX - size.width / 2
        var y = visible.minY + (visible.height - size.height) * 0.36
        x = max(visible.minX, min(x, visible.maxX - size.width))
        y = max(visible.minY, min(y, visible.maxY - size.height))
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: 按钮动作（统一走 delegate，不自行关闭）

    @objc private func saveTapped() { panelDelegate?.resultPanelDidSave(self) }
    @objc private func copyTapped() { panelDelegate?.resultPanelDidCopy(self) }
    @objc private func pinTapped() { panelDelegate?.resultPanelDidPin(self) }
    @objc private func editTapped() { panelDelegate?.resultPanelDidEdit(self) }
    @objc private func retryForcedTapped() { panelDelegate?.resultPanelDidRetryForced(self) }
    @objc private func closeTapped() { panelDelegate?.resultPanelDidClose(self) }

    // MARK: 内部引用

    private var container: ToolbarContainerView?
}
