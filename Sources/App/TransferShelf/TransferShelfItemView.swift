import AppKit

/// 单个暂存条目视图：图标 + 名称 + 副标题（第二棒 UI ②），四类条目
/// （file/text/image/link）共用；点击与拖出行为按 kind 分流。
/// 移除/拖出校验/快速查看/分享/hover 均经闭包注入，不直接调用控制器单例。
final class TransferShelfItemView: NSView {

    /// 移除条目 → ShelfView 转发到控制器。
    var onRemove: ((UUID) -> Void)?
    /// 拖出前校验（文件已失效返回 false 并由控制器移除条目）；未注入时放行。
    var validateForDrag: ((UUID) -> Bool)?
    /// Quick Look（仅 file 条目；text/image/link 为 nil 时菜单项隐藏）。
    var onQuickLook: ((TransferItem) -> Void)?
    /// 分享面板锚点回调。
    var onShare: ((TransferItem, NSView) -> Void)?
    /// hover 变化（进入传 id，离开传 nil；供 Space 键 Quick Look 定位）。
    var onHover: ((UUID?) -> Void)?

    private let item: TransferItem
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    /// 副标题：file=大小+时间、text=字数、image=像素尺寸、link=相对时间。
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let removeButton = NSButton()
    // 单击 vs 拖出判定与「本次按住已开拖拽会话」标记;后者同时避免
    // 连续 mouseDragged 重复开启多个拖拽会话。
    private var clickGate = TransferShelfClickGate()
    private var dragSessionActive = false

    /// 文件大小异步加载缓存（路径 → 字节），避免每次渲染重复 stat。
    private static let fileSizeCache = NSCache<NSString, NSNumber>()

    /// 后台 stat 取文件大小；失败返回 nil（副标题保持占位）。
    private static func loadFileSize(for item: TransferItem, completion: @escaping (Int64?) -> Void) {
        if let cached = fileSizeCache.object(forKey: item.url.path as NSString) {
            completion(cached.int64Value)
            return
        }
        let path = item.url.path
        DispatchQueue.global(qos: .utility).async {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value
            if let size {
                fileSizeCache.setObject(NSNumber(value: size), forKey: path as NSString)
            }
            DispatchQueue.main.async { completion(size) }
        }
    }

    /// hover/普通背景用显式动态色：labelColor 按 alpha 叠加，深浅色模式都可见
    /// （修复旧实现硬编码 white 在浅色模式下几乎不可见的问题）。
    private static var normalBackground: NSColor {
        NSColor.labelColor.withAlphaComponent(0.06)
    }

    private static var hoverBackground: NSColor {
        NSColor.labelColor.withAlphaComponent(0.14)
    }

    init(item: TransferItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: TransferShelfLayoutSpec.verticalItemWidth,
                                 height: TransferShelfLayoutSpec.verticalItemHeight))

        iconView.image = Self.icon(for: item)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        nameLabel.stringValue = item.name
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.maximumNumberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.cell?.wraps = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        subtitleLabel.stringValue = Self.subtitle(for: item)
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.cell?.truncatesLastVisibleLine = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        wantsLayer = true
        layer?.cornerRadius = TransferShelfLayoutSpec.itemCornerRadius
        layer?.backgroundColor = Self.normalBackground.cgColor

        removeButton.bezelStyle = .texturedRounded
        removeButton.isBordered = false
        let removeSymbol = NSImage(systemSymbolName: "xmark.circle.fill",
                                   accessibilityDescription: "删除") ?? NSImage()
        removeSymbol.size = NSSize(width: TransferShelfLayoutSpec.itemClearButtonSize,
                                   height: TransferShelfLayoutSpec.itemClearButtonSize)
        removeButton.image = removeSymbol
        removeButton.imageScaling = .scaleProportionallyDown
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.toolTip = "删除"
        removeButton.target = self
        removeButton.action = #selector(removeSelf)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: TransferShelfLayoutSpec.verticalItemWidth),
            heightAnchor.constraint(equalToConstant: TransferShelfLayoutSpec.verticalItemHeight),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: TransferShelfLayoutSpec.itemIconSize),
            iconView.heightAnchor.constraint(equalToConstant: TransferShelfLayoutSpec.itemIconSize),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),

            subtitleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -4),
            subtitleLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),

            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TransferShelfLayoutSpec.itemClearButtonOffset),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: TransferShelfLayoutSpec.itemClearButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: TransferShelfLayoutSpec.itemClearButtonSize),
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))

        // file 条目大小后台回填（初始副标题先显示时间）
        if item.kind == .file {
            Self.loadFileSize(for: item) { [weak self] size in
                guard let self, let size else { return }
                let time = TransferItemRelativeTime.string(from: item.addedAt, now: Date())
                self.subtitleLabel.stringValue = "\(TransferItemFileSize.string(bytes: size)) · \(time)"
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - kind 外观

    private static func icon(for item: TransferItem) -> NSImage? {
        let side = TransferShelfLayoutSpec.itemIconSize
        switch item.kind {
        case .file:
            // NSWorkspace.icon(forFile:) 返回共享缓存实例，直接改 size 会污染全局
            // 图标缓存（其他窗口里同一文件的图标会一起被缩放）；先拷贝再调整尺寸。
            let icon = NSWorkspace.shared.icon(forFile: item.url.path).copy() as? NSImage
            icon?.size = NSSize(width: side, height: side)
            return icon
        case .image:
            guard let data = item.imageData, let image = NSImage(data: data) else { return nil }
            let thumbnail = NSImage(size: NSSize(width: side, height: side))
            thumbnail.lockFocus()
            image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver, fraction: 1.0)
            thumbnail.unlockFocus()
            return thumbnail
        case .text:
            let symbol = NSImage(systemSymbolName: "doc.text",
                                 accessibilityDescription: "文本") ?? NSImage()
            symbol.size = NSSize(width: side, height: side)
            return symbol
        case .link:
            let symbol = NSImage(systemSymbolName: "globe",
                                 accessibilityDescription: "链接") ?? NSImage()
            symbol.size = NSSize(width: side, height: side)
            return symbol
        }
    }

    private static func subtitle(for item: TransferItem) -> String {
        let time = TransferItemRelativeTime.string(from: item.addedAt, now: Date())
        switch item.kind {
        case .file:
            return "… · \(time)"   // 大小后台加载后回填
        case .text:
            return "\(item.text?.count ?? 0) 字 · \(time)"
        case .image:
            if let data = item.imageData, let rep = NSBitmapImageRep(data: data) {
                return "\(rep.pixelsWide) × \(rep.pixelsHigh) · \(time)"
            }
            return "图片 · \(time)"
        case .link:
            return time
        }
    }

    // MARK: - hover（UI ②：过渡动画 + 动态色修复浅色模式不可见）

    override func mouseEntered(with event: NSEvent) {
        animateBackground(to: Self.hoverBackground)
        removeButton.contentTintColor = .labelColor
        onHover?(item.id)
    }

    override func mouseExited(with event: NSEvent) {
        animateBackground(to: Self.normalBackground)
        removeButton.contentTintColor = .tertiaryLabelColor
        onHover?(nil)
    }

    private func animateBackground(to color: NSColor) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            layer?.backgroundColor = color.cgColor
        }
    }

    // MARK: - 单击 / 双击 / 拖出（按 kind 分流）

    /// 按下只记录手势起点,不在按下时立即执行单击动作:mouseDown 早于系统
    /// 对「单击 vs 拖出」的判定,立即弹出 Finder 会抢走焦点、掐断把文件
    /// 拖到目标目录的手势。单击动作推迟到 mouseUp(见 ClickGate)。
    override func mouseDown(with event: NSEvent) {
        clickGate.press()
    }

    /// 拖动：把暂存内容拖出到 Finder/其他 App，pasteboard 类型按 kind 写入。
    /// 必须设置非零 draggingFrame 与图像组件，否则 beginDraggingSession 抛异常导致崩溃。
    /// file 条目已被移走/删除时不开启拖拽会话（无法落盘），经校验闭包顺带移除该条目。
    override func mouseDragged(with event: NSEvent) {
        guard validateForDrag?(item.id) ?? true else { return }
        if !dragSessionActive {
            dragSessionActive = true
            clickGate.beginDrag()
        } else {
            return
        }
        let pasteboardItem = NSPasteboardItem()
        write(to: pasteboardItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.draggingFrame = TransferShelfLayoutSpec.dragImageFrame
        draggingItem.imageComponentsProvider = { [weak self] in
            let image = self?.iconView.image ?? NSImage()
            let component = NSDraggingImageComponent(key: .icon)
            component.contents = image
            component.frame = TransferShelfLayoutSpec.dragImageFrame
            return [component]
        }
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    /// 把条目内容写进拖拽 pasteboard：file→fileURL、text→string、
    /// image→PNG+tiff、link→URL+string。
    private func write(to pasteboardItem: NSPasteboardItem) {
        switch item.kind {
        case .file:
            pasteboardItem.setString(item.url.absoluteString, forType: .fileURL)
        case .text:
            pasteboardItem.setString(item.text ?? "", forType: .string)
        case .image:
            if let data = item.imageData {
                pasteboardItem.setData(data, forType: .png)
                if let tiff = NSImage(data: data)?.tiffRepresentation {
                    pasteboardItem.setData(tiff, forType: .tiff)
                }
            }
        case .link:
            pasteboardItem.setString(item.link?.absoluteString ?? "", forType: .URL)
            pasteboardItem.setString(item.link?.absoluteString ?? "", forType: .string)
        }
    }

    /// 松开时若未进入拖拽,按单击处理（按 kind 分流）；连击第二次（双击）
    /// 对 file 条目执行打开。
    override func mouseUp(with event: NSEvent) {
        dragSessionActive = false
        guard clickGate.isClick else { return }
        switch item.kind {
        case .file:
            if event.clickCount >= 2 {
                NSWorkspace.shared.open(item.url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        case .text:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.text ?? "", forType: .string)
            TransientHudToast.show(text: "已复制文本")
        case .image:
            if let data = item.imageData, let image = NSImage(data: data) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                TransientHudToast.show(text: "已复制图片")
            }
        case .link:
            if let url = item.link {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - 右键菜单（按 kind 分流）

    /// 右键菜单：file 全量（打开/快速查看/分享/Finder 定位/拷贝路径/移除）；
    /// text/link/image 给出各自的主操作 + 分享 + 移除。
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        switch item.kind {
        case .file:
            menu.addItem(self.menuItem("打开", #selector(openFile)))
            if onQuickLook != nil {
                menu.addItem(self.menuItem("快速查看", #selector(quickLookSelf)))
            }
            if onShare != nil {
                menu.addItem(self.menuItem("分享…", #selector(shareSelf)))
            }
            menu.addItem(.separator())
            menu.addItem(self.menuItem("在 Finder 显示", #selector(revealInFinder)))
            menu.addItem(self.menuItem("拷贝路径", #selector(copyPath)))
        case .text:
            menu.addItem(self.menuItem("复制文本", #selector(copyText)))
            if onShare != nil {
                menu.addItem(self.menuItem("分享…", #selector(shareSelf)))
            }
        case .image:
            menu.addItem(self.menuItem("拷贝图片", #selector(copyImage)))
            if onShare != nil {
                menu.addItem(self.menuItem("分享…", #selector(shareSelf)))
            }
        case .link:
            menu.addItem(self.menuItem("打开链接", #selector(openFile)))
            menu.addItem(self.menuItem("拷贝链接", #selector(copyPath)))
            if onShare != nil {
                menu.addItem(self.menuItem("分享…", #selector(shareSelf)))
            }
        }
        menu.addItem(.separator())
        menu.addItem(self.menuItem("移除", #selector(removeSelf)))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openFile() {
        NSWorkspace.shared.open(item.kind == .link ? (item.link ?? item.url) : item.url)
    }

    @objc private func quickLookSelf() {
        onQuickLook?(item)
    }

    @objc private func shareSelf() {
        onShare?(item, self)
    }

    @objc private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    @objc private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.kind == .link
            ? (item.link?.absoluteString ?? "")
            : item.url.path, forType: .string)
    }

    @objc private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text ?? "", forType: .string)
        TransientHudToast.show(text: "已复制文本")
    }

    @objc private func copyImage() {
        if let data = item.imageData, let image = NSImage(data: data) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            TransientHudToast.show(text: "已复制图片")
        }
    }

    @objc private func removeSelf() {
        onRemove?(item.id)
    }
}

extension TransferShelfItemView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]
    }
}
