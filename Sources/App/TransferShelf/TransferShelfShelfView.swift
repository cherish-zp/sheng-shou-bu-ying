import AppKit
import Quartz

/// 暂存面板内容视图：毛玻璃圆角面板（NSVisualEffectView + 容器 layer 圆角裁剪），
/// 头部栏（标题/计数/清空），四类内容拖入（file/text/image/link，经 TransferItemKindIntake），
/// Quick Look 宿主。交互经闭包回调控制器，不引用单例。
final class TransferShelfShelfView: NSView {

    /// 拖入解析结果（四类条目 + 拒绝提示）→ 控制器 accept。
    var onIntake: ((TransferIntakeResult) -> Void)?
    /// 文件 URL 直入通道（单测注入与兼容入口；视图自身拖拽走 onIntake）。
    var onAccept: (([URL]) -> Void)?
    /// 移除条目 → 控制器 removeItem。
    var onRemove: ((UUID) -> Void)?
    /// 清空全部（头部垃圾桶按钮）。
    var onClearAll: (() -> Void)?
    /// 拖出前校验条目（文件已失效返回 false，控制器顺带移除该条目）。
    var validateForDrag: ((UUID) -> Bool)?
    /// 用户正在面板上交互（拖入高亮、点删除等），取消自动隐藏。
    var onInteracting: (() -> Void)?
    /// Quick Look 数据源：由控制器提供当前暂存序列（QL 打开时实时取）。
    var quickLookSource: (() -> [TransferItem])?
    /// hover 条目变化（进入传 id，离开传 nil；Space 预览定位用）。
    var onHoverItem: ((UUID?) -> Void)?
    /// 当前 hover 的条目 id（ItemView 经 onHover 上报）。
    var hoveredItemID: UUID?

    private var items: [TransferItem] = []
    private let effectView = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "中转站")
    private let countLabel = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    private let stackView = NSStackView()
    private let emptyIcon = NSImageView()
    private let emptyLabel = NSTextField(labelWithString: "拖文件到这里暂存")
    private let emptyHintLabel = NSTextField(labelWithString: "也可拖入选中文字 / 图片 / 链接")
    /// Quick Look 当前展示的文件 URL 序列与起始索引（打开时快照）。
    private var quickLookURLs: [URL] = []
    private var quickLookIndex: Int = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 毛玻璃方案：容器 layer 负责圆角裁剪（masksToBounds），effectView 铺满提供
        // hudWindow 材质——旧实现为规避「NSVisualEffectView 透明直角」而弃用毛玻璃，
        // 由容器裁剪后两者兼得。
        layer?.cornerRadius = TransferShelfLayoutSpec.cornerRadius
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.borderWidth = TransferShelfLayoutSpec.panelHairlineWidth

        effectView.material = TransferShelfLayoutSpec.panelMaterial
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        // 头部栏：标题 + 条目计数 + 清空按钮
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        countLabel.font = .systemFont(ofSize: 10)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countLabel)

        clearButton.bezelStyle = .texturedRounded
        clearButton.isBordered = false
        let trashSymbol = NSImage(systemSymbolName: "trash",
                                  accessibilityDescription: "清空全部") ?? NSImage()
        trashSymbol.size = NSSize(width: 12, height: 12)
        clearButton.image = trashSymbol
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.toolTip = "清空全部"
        clearButton.target = self
        clearButton.action = #selector(clearAllClicked)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)

        stackView.orientation = .vertical
        stackView.spacing = TransferShelfLayoutSpec.itemSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = stackView
        addSubview(scrollView)

        // documentView 必须钉到 clip 视图:stackView 关闭了 autoresizing 且
        // 没有其他约束时 frame 恒为 0×0,渲染进来的条目全部不可见(拖入后
        // 面板永远空白)。底部用 >=,内容超出可视高度时才出现滚动。
        let clipView = scrollView.contentView
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
            stackView.bottomAnchor.constraint(greaterThanOrEqualTo: clipView.bottomAnchor),
        ])

        // 空态：图标 + 主文案 + 辅助文案，整体居中（无手调偏移）
        let emptySymbol = NSImage(systemSymbolName: "tray.and.arrow.down",
                                  accessibilityDescription: "拖入内容暂存") ?? NSImage()
        emptySymbol.size = NSSize(width: 18, height: 18)
        emptyIcon.image = emptySymbol
        emptyIcon.contentTintColor = .secondaryLabelColor
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyIcon)

        emptyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        emptyHintLabel.font = .systemFont(ofSize: 10)
        emptyHintLabel.textColor = .tertiaryLabelColor
        emptyHintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyHintLabel)

        // 空态：图标 + 主文案横向组合居中，辅助文案在下方
        let emptyStack = NSStackView(views: [emptyIcon, emptyLabel])
        emptyStack.orientation = .horizontal
        emptyStack.spacing = 6
        emptyStack.alignment = .centerY
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyStack)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TransferShelfLayoutSpec.panelPadding),
            titleLabel.centerYAnchor.constraint(equalTo: topAnchor, constant: TransferShelfLayoutSpec.headerHeight / 2),

            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            countLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TransferShelfLayoutSpec.panelPadding),
            clearButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: TransferShelfLayoutSpec.headerHeight),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -TransferShelfLayoutSpec.panelPadding),

            emptyStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -9),

            emptyHintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyHintLabel.topAnchor.constraint(equalTo: emptyStack.bottomAnchor, constant: 4),
        ])
        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        false
    }

    // MARK: - 尺寸

    /// 面板尺寸：空态用固定空态尺寸；有条目时宽度由最长文本自适应（clamp 200–260）。
    func preferredPanelSize() -> CGSize {
        if items.isEmpty {
            return CGSize(
                width: TransferShelfLayoutSpec.emptyPanelWidth,
                height: TransferShelfLayoutSpec.emptyPanelHeight
            )
        }
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let textWidths = items.map { TransferShelfLayoutSpec.itemTextWidth(for: $0.name, font: font) }
        return CGSize(
            width: TransferShelfLayoutSpec.panelWidth(itemTextWidths: textWidths),
            height: TransferShelfLayoutSpec.panelHeight(itemCount: items.count)
        )
    }

    /// 条目视图宽度跟随面板宽度（减去面板左右内边距）。
    static func itemWidth(forPanelWidth panelWidth: CGFloat) -> CGFloat {
        panelWidth - TransferShelfLayoutSpec.panelPadding * 2
    }

    func render(items: [TransferItem]) {
        self.items = items
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let itemWidth = Self.itemWidth(forPanelWidth: preferredPanelSize().width)
        for item in items {
            let itemView = TransferShelfItemView(item: item)
            itemView.frame.size.width = itemWidth
            itemView.onRemove = { [weak self] id in
                self?.onRemove?(id)
                self?.onInteracting?()
            }
            itemView.validateForDrag = { [weak self] id in
                self?.validateForDrag?(id) ?? true
            }
            itemView.onQuickLook = { [weak self] item in
                self?.openQuickLook(startingAt: item)
            }
            itemView.onShare = { item, anchor in
                Self.share(item: item, from: anchor)
            }
            itemView.onHover = { [weak self] id in
                self?.hoveredItemID = id
                self?.onHoverItem?(id)
            }
            stackView.addArrangedSubview(itemView)
        }
        let isEmpty = items.isEmpty
        emptyIcon.isHidden = !isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyHintLabel.isHidden = !isEmpty
        clearButton.isHidden = isEmpty
        countLabel.stringValue = isEmpty ? "" : "· \(items.count) 项"
    }

    // MARK: - Quick Look 宿主

    /// 是否可以打开 Quick Look（hover 的是 file 条目）。
    func canOpenQuickLook() -> Bool {
        let source = quickLookSource?() ?? items
        return TransferShelfQuickLookIndex.startIndex(for: source, hovered: hoveredItemID) != nil
    }

    /// 打开 Quick Look：hover 定位起始条目；再按 ESC 或 QL 内关闭。
    func openQuickLook(startingAt item: TransferItem) {
        guard let panel = QLPreviewPanel.shared() as QLPreviewPanel? else { return }
        let source = quickLookSource?() ?? items
        let urls = TransferShelfQuickLookIndex.previewURLs(for: source)
        guard let index = TransferShelfQuickLookIndex.startIndex(for: source, hovered: item.id) else { return }
        quickLookURLs = urls
        quickLookIndex = index
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
        panel.currentPreviewItemIndex = index
    }

    /// Space 键触发（hover 为 file 条目时）；返回是否已处理。
    func toggleQuickLookForHovered() -> Bool {
        guard canOpenQuickLook() else { return false }
        let source = quickLookSource?() ?? items
        guard let id = hoveredItemID,
              let item = source.first(where: { $0.id == id }) else { return false }
        openQuickLook(startingAt: item)
        return true
    }

    /// Quick Look 可见时关闭。
    func closeQuickLookIfVisible() {
        let panel = QLPreviewPanel.shared()
        if panel?.isVisible == true {
            panel?.orderOut(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: - 拖入接收（四类内容，经 TransferItemKindIntake）

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let result = TransferItemKindIntake.result(from: sender.draggingPasteboard)
        guard !result.items.isEmpty || result.rejectionMessage != nil else { return [] }
        onInteracting?()
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderWidth = TransferShelfLayoutSpec.panelHairlineWidth
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    }

    /// 按实际接受情况返回：可识别内容（含超限拒绝——已有 Toast 反馈）返回 true，
    /// 完全无法识别的拖入返回 false（拖源显示不可落放）。
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        resetBorder()
        let result = TransferItemKindIntake.result(from: sender.draggingPasteboard)
        guard !result.items.isEmpty || result.rejectionMessage != nil else { return false }
        onIntake?(result)
        return true
    }

    private func resetBorder() {
        layer?.borderWidth = TransferShelfLayoutSpec.panelHairlineWidth
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    }

    /// 提取 pasteboard 中的文件 URL（兼容旧调用方）。
    static func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return []
        }
        return urls.filter { $0.isFileURL }
    }

    @objc private func clearAllClicked() {
        onClearAll?()
    }

    /// 系统分享面板（文件分享文件本体，text/image/link 分享内容）。
    static func share(item: TransferItem, from anchorView: NSView) {
        let content: Any
        switch item.kind {
        case .file: content = item.url
        case .text: content = item.text ?? ""
        case .image:
            if let data = item.imageData, let image = NSImage(data: data) {
                content = image
            } else {
                return
            }
        case .link: content = item.link ?? item.url
        }
        let picker = NSSharingServicePicker(items: [content])
        picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
    }
}

extension TransferShelfShelfView: QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0, index < quickLookURLs.count else { return nil }
        return quickLookURLs[index] as QLPreviewItem
    }

    func previewPanel(_ panel: QLPreviewPanel!, currentPreviewItemIndexDidChange newItemIndex: Int) {
        quickLookIndex = newItemIndex
    }
}
