import AppKit
import ImageIO

/// 剪贴板历史：1 秒轮询 changeCount 捕获变更（文本/图片/文件），持久化到 App Support。
/// 面板为浮引式横向卡片流：约 1500×340 居中悬浮、流光玻璃背景、顶部搜索 + 类型 chips、
/// 卡片横向滚动；点击卡片回写剪贴板并模拟 ⌘V 自动粘贴；面板可见时 ⌥1~⌥9 直达对应卡片。
final class ClipboardHistoryModule: NSObject {

    let id = "clipboardHistory"
    let title = "剪贴板历史"

    /// 面板热键的独立 signature（"clip"），与 AppDelegate 全局热键（默认 signature）隔离。
    private static let cardHotkeySignature = OSType(0x636C6970)
    /// 卡片统一宽度。
    private static let cardWidth: CGFloat = 236
    /// 面板理想尺寸（小屏按可见区夹持）。
    private static let idealPanelSize = NSSize(width: 1500, height: 340)

    private let storageURL: URL
    private var store = ClipboardHistoryStore()
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var pollTimer: Timer?
    private var window: NSPanel?

    // MARK: 面板状态
    private var searchField: NSSearchField?
    private var kindSegmented: NSSegmentedControl?
    private var cardStack: NSStackView?
    private var cardScroll: NSScrollView?
    private var hintLabel: NSTextField?
    /// 当前类型过滤：nil = 全部。
    private var selectedKind: ClipboardHistoryItem.Kind?
    /// 当前过滤后的展示条目（卡片顺序 = 序号热键顺序）。
    private var displayed: [ClipboardHistoryItem] = []
    /// 面板显示时记录的主修饰键符号（⌥/⌃/⌘），徽章与说明行用。
    private var modifierSymbol = "⌥"
    /// 正在隐藏面板（orderOut 会触发 didResignKey，用标志避免自我递归关窗）。
    private var isDismissing = false
    /// 显示面板时的前台应用：自动粘贴前把焦点还给它的目标。
    private var frontmostAppAtShow: NSRunningApplication?
    private var escMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    // MARK: 卡片序号热键（独立实例，面板可见时才注册）
    private var cardHotkeyRegistrar: CarbonHotkeyRegistrar?
    private var cardHotkeyManager: HotkeyManager?
    private var cardHotkeys: [Hotkey] = []

    /// 缩略图缓存：避免每次 reload 重复解码 PNG。
    private var thumbnailCache: [UUID: NSImage] = [:]
    /// 图片像素尺寸缓存（ImageIO 属性读取，不解码像素）——缩略图高度计算用。
    private var imageSizeCache: [UUID: NSSize] = [:]

    init(storageURL: URL? = nil) {
        let dir = AppSupportDirectory.url
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = storageURL ?? dir.appendingPathComponent("clipboard_history.json")
        if let data = try? Data(contentsOf: self.storageURL),
           let loaded = try? JSONDecoder().decode(ClipboardHistoryStore.self, from: data) {
            store = loaded
        }
        super.init()
    }

    deinit {
        if let monitor = escMonitor { NSEvent.removeMonitor(monitor) }
        if let observer = resignObserver { NotificationCenter.default.removeObserver(observer) }
    }

    func start() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        hidePanel()
    }

    private func pollPasteboard() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount

        if let text = board.string(forType: .string), !text.isEmpty {
            store.add(ClipboardHistoryItem(kind: .text, text: text))
        } else if let urls = board.readObjects(forClasses: [NSURL.self]) as? [URL],
                  !urls.isEmpty, urls.allSatisfy(\.isFileURL) {
            store.add(ClipboardHistoryItem(kind: .files, text: urls.map(\.lastPathComponent).joined(separator: ", "),
                                           filePaths: urls.map(\.path)))
        } else if let image = NSImage(pasteboard: board),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]),
                  png.count <= 2_000_000 {
            store.add(ClipboardHistoryItem(kind: .image, text: "图片 \(rep.pixelsWide)×\(rep.pixelsHigh)",
                                           imageData: png))
        } else {
            return
        }
        persist()
        if window?.isVisible == true { reload() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    // MARK: - 面板显示/隐藏

    func showWindow() {
        // 记录呼出时的前台应用：粘贴时把焦点还给它（⌘V 落到用户正在使用的 app）。
        frontmostAppAtShow = NSWorkspace.shared.frontmostApplication
        if window == nil { buildWindow() }
        guard let panel = window else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        UITheme.center(panel)
        reload()
    }

    /// 隐藏面板：orderOut + 注销全部序号热键。
    func hidePanel() {
        unregisterCardHotkeys()
        guard let panel = window, panel.isVisible else { return }
        isDismissing = true
        panel.orderOut(nil)
        isDismissing = false
    }

    // MARK: - 窗口构建

    private func buildWindow() {
        let size = clampedPanelSize()
        let panel = ClipboardPanelWindow(contentRect: NSRect(origin: .zero, size: size),
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .aqua)
        window = panel

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.backgroundColor = UITheme.panelBackground.cgColor
        content.layer?.cornerRadius = UITheme.panelCornerRadius
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = UITheme.hairline.cgColor
        panel.contentView = content
        UITheme.installFlowingGlass(in: content)

        buildTopBar(in: content)
        buildCardFlow(in: content)
        buildHint(in: content)
        installDismissHandlers()
    }

    /// 面板尺寸：理想 1500×340，按鼠标所在屏可见区夹持（不小于 700×260）。
    private func clampedPanelSize() -> NSSize {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame.size ?? NSSize(width: 1512, height: 900)
        let width = min(Self.idealPanelSize.width, max(700, visible.width - 40))
        let height = min(Self.idealPanelSize.height, max(260, visible.height - 80))
        return NSSize(width: width, height: height)
    }

    /// 顶栏：搜索框（左）+ 类型 chips（中）+ 关闭按钮（右）。
    private func buildTopBar(in content: NSView) {
        let search = NSSearchField()
        search.placeholderString = "搜索文本 / 文件名"
        search.font = .systemFont(ofSize: 12)
        search.sendsWholeSearchString = false
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searchChanged)
        search.translatesAutoresizingMaskIntoConstraints = false

        let segmented = NSSegmentedControl(labels: ["全部", "文本", "图片", "文件"],
                                           trackingMode: .selectOne,
                                           target: self, action: #selector(kindChanged(_:)))
        segmented.segmentStyle = .roundRect
        segmented.selectedSegment = 0
        segmented.font = .systemFont(ofSize: 11)
        segmented.translatesAutoresizingMaskIntoConstraints = false

        let close = NSButton(title: "✕", target: self, action: #selector(closeClicked))
        close.isBordered = false
        close.contentTintColor = UITheme.textSecondary
        close.font = .systemFont(ofSize: 13, weight: .medium)
        close.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(search)
        content.addSubview(segmented)
        content.addSubview(close)
        NSLayoutConstraint.activate([
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            search.centerYAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            search.widthAnchor.constraint(equalToConstant: 220),
            search.heightAnchor.constraint(equalToConstant: 26),

            segmented.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            segmented.centerYAnchor.constraint(equalTo: search.centerYAnchor),

            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            close.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 24),
        ])
        searchField = search
        kindSegmented = segmented
    }

    /// 卡片流：横向 NSScrollView + NSStackView，卡片高撑满内容区。
    private func buildCardFlow(in content: NSView) {
        let scroll = NSScrollView()
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack

        content.addSubview(scroll)
        // 横向滚动：固定 top/leading + 高度，宽度由卡片内容撑开（不约束 trailing）。
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 42),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -26),
        ])
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor),
        ])
        cardStack = stack
        cardScroll = scroll
    }

    /// 底部说明行：快捷键提示（符号随主修饰键变）。
    private func buildHint(in content: NSView) {
        let hint = NSTextField(labelWithString: "")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = UITheme.textSecondary
        hint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
        hintLabel = hint
    }

    /// 关闭路径：Esc（局部 keyDown 监听，面板可见时消费）+ 失去 key 自动关闭。
    private func installDismissHandlers() {
        guard escMonitor == nil, resignObserver == nil, let panel = window else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true, event.keyCode == 53 else { return event }
            self.hidePanel()
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self, !self.isDismissing else { return }
            self.hidePanel()
        }
    }

    // MARK: - 刷新

    private func reload() {
        modifierSymbol = HotkeyPreferences.load().primaryModifier.symbol
        displayed = ClipboardCardFilter.filter(items: store.displayOrder,
                                              searchText: searchField?.stringValue ?? "",
                                              kind: selectedKind)
        rebuildCards()
        refreshHint()
        registerCardHotkeys(count: displayed.count)
    }

    private func rebuildCards() {
        guard let stack = cardStack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (offset, item) in displayed.enumerated() {
            let card = ClipboardCardView(item: item, index: offset + 1, badgeSymbol: modifierSymbol,
                                         thumbnail: thumbnail(for: item),
                                         pixelSize: cachedPixelSize(for: item))
            card.onActivate = { [weak self, weak card] in
                guard let self, let card,
                      let index = self.displayed.firstIndex(where: { $0.id == card.item.id }) else { return }
                self.activateItem(at: index)
            }
            card.onToggleFavorite = { [weak self, weak card] in
                guard let self, let card else { return }
                self.store.toggleFavorite(id: card.item.id)
                self.persist()
                self.reload()
            }
            card.onDelete = { [weak self, weak card] in
                guard let self, let card else { return }
                self.store.remove(id: card.item.id)
                self.thumbnailCache[card.item.id] = nil
                self.imageSizeCache[card.item.id] = nil
                self.persist()
                self.reload()
            }
            // 卡片高度撑满内容区。
            card.widthAnchor.constraint(equalToConstant: Self.cardWidth).isActive = true
            card.heightAnchor.constraint(equalTo: stack.heightAnchor).isActive = true
            stack.addArrangedSubview(card)
        }
    }

    private func refreshHint() {
        let prefs = HotkeyPreferences.load()
        let symbol = prefs.primaryModifier.symbol
        let digitHint: String
        if displayed.count >= 2 {
            digitHint = "\(symbol)1~\(symbol)\(min(displayed.count, 9)) 粘贴对应卡片"
        } else if displayed.count == 1 {
            digitHint = "\(symbol)1 粘贴对应卡片"
        } else {
            digitHint = "暂无匹配条目"
        }
        let summon = prefs.displayLabel(for: id) ?? (symbol + "X")
        hintLabel?.stringValue = "\(digitHint) · \(summon) 再次呼出 · Esc 关闭"
    }

    // MARK: - 缩略图

    private func cachedPixelSize(for item: ClipboardHistoryItem) -> NSSize {
        if let size = imageSizeCache[item.id] { return size }
        var size = NSSize(width: 0, height: 0)
        if let data = item.imageData,
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            size = NSSize(width: props[kCGImagePropertyPixelWidth] as? CGFloat ?? 0,
                          height: props[kCGImagePropertyPixelHeight] as? CGFloat ?? 0)
        }
        imageSizeCache[item.id] = size
        return size
    }

    private func thumbnail(for item: ClipboardHistoryItem) -> NSImage? {
        if let cached = thumbnailCache[item.id] { return cached }
        guard let data = item.imageData,
              let thumb = ClipboardThumbnail.make(fromPNG: data) else { return nil }
        thumbnailCache[item.id] = thumb
        return thumb
    }

    // MARK: - 点击/热键 → 回写 + 粘贴

    /// 点击卡片或按序号热键：回写剪贴板 → 隐藏面板 → 模拟 ⌘V 粘贴到原前台 app。
    private func activateItem(at index: Int) {
        guard index >= 0, index < displayed.count else { return }
        let item = displayed[index]
        writeBack(item)
        hidePanel()
        simulatePaste()
    }

    /// 回写剪贴板（图片→NSImage、文件→URL、文本→string）。
    private func writeBack(_ item: ClipboardHistoryItem) {
        let board = NSPasteboard.general
        board.clearContents()
        if let data = item.imageData, let image = NSImage(data: data) {
            board.writeObjects([image])
        } else if let paths = item.filePaths {
            board.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
        } else {
            board.setString(item.text, forType: .string)
        }
    }

    /// 模拟 ⌘V：先把焦点还给呼出时的前台 app，再 post keyDown/keyUp（命令键 + V=9）。
    /// 辅助功能未授权时跳过粘贴（剪贴板已回写）。
    private func simulatePaste() {
        guard AXIsProcessTrusted() else {
            DiagLog.write("ClipboardHistory: 辅助功能未授权，仅回写剪贴板不粘贴")
            return
        }
        let previous = frontmostAppAtShow
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if let previous, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                if #available(macOS 14.0, *) {
                    previous.activate()
                } else {
                    previous.activate(options: [])
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                for keyDown in [true, false] {
                    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: keyDown) else { continue }
                    event.flags = .maskCommand
                    event.post(tap: .cghidEventTap)
                }
            }
        }
    }

    /// 序号热键（面板可见时）→ 粘贴对应序号卡片。
    private func pasteByDigit(_ digit: Int) {
        guard window?.isVisible == true, digit >= 1, digit <= displayed.count else { return }
        activateItem(at: digit - 1)
    }

    // MARK: - 卡片序号热键注册（独立 CarbonHotkeyRegistrar + HotkeyManager）

    /// 按当前展示条目数注册 ⌥1~⌥9（超出条目数不注册）；先注销旧热键再注册。
    private func registerCardHotkeys(count: Int) {
        unregisterCardHotkeys()
        let digitCount = min(count, 9)
        guard digitCount > 0 else { return }
        // registrar 只建一次（InstallEventHandler 随实例存活，不可反复创建/释放）。
        if cardHotkeyRegistrar == nil || cardHotkeyManager == nil {
            let registrar = CarbonHotkeyRegistrar(signature: Self.cardHotkeySignature)
            cardHotkeyRegistrar = registrar
            cardHotkeyManager = HotkeyManager(registrar: registrar)
        }
        guard let manager = cardHotkeyManager else { return }
        let mask = HotkeyPreferences.load().primaryModifier.carbonMask
        for digit in 1...digitCount {
            guard let keyCode = ClipboardDigitKeyCodes.keyCodes[digit] else { continue }
            let hotkey = Hotkey(keyCode: keyCode, modifiers: mask)
            manager.register(hotkey) { [weak self] in self?.pasteByDigit(digit) }
            cardHotkeys.append(hotkey)
        }
        DiagLog.write("ClipboardHistory: 卡片热键注册 \(cardHotkeys.count) 个")
    }

    private func unregisterCardHotkeys() {
        guard let manager = cardHotkeyManager else { return }
        for hotkey in cardHotkeys { manager.unregister(hotkey) }
        cardHotkeys.removeAll()
    }

    // MARK: - 顶栏动作

    @objc private func searchChanged() {
        reload()
    }

    @objc private func kindChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 1: selectedKind = .text
        case 2: selectedKind = .image
        case 3: selectedKind = .files
        default: selectedKind = nil
        }
        reload()
    }

    @objc private func closeClicked() {
        hidePanel()
    }
}

// MARK: - 面板窗口（borderless NSPanel，可成为 key 以支持搜索框输入）

final class ClipboardPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - 卡片视图

/// 单张剪贴板卡片：序号徽章（⌥N）+ 类型徽章 + 收藏星 + 内容区 + 信息行 + hover 删除。
final class ClipboardCardView: NSView {

    let item: ClipboardHistoryItem
    /// 显示序号（1 起）；>9 不显示序号徽章。
    private let index: Int
    private let badgeSymbol: String

    var onActivate: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    /// 两段式确认：第一次点 × 进入 armed，3 秒内再点执行删除。
    var onDelete: (() -> Void)?

    private let deleteButton = NSButton()
    private var isArmedForDelete = false
    private var disarmWorkItem: DispatchWorkItem?
    private var hoverArea: NSTrackingArea?

    init(item: ClipboardHistoryItem, index: Int, badgeSymbol: String,
         thumbnail: NSImage?, pixelSize: NSSize) {
        self.item = item
        self.index = index
        self.badgeSymbol = badgeSymbol
        super.init(frame: .zero)
        wantsLayer = true
        UITheme.styleCard(self, tint: selfTintColor)
        buildSubviews(thumbnail: thumbnail, pixelSize: pixelSize)
    }

    required init?(coder: NSCoder) { fatalError("不支持 storyboard") }

    /// 类型徽章色：图片=绿、文本=蓝、文件=橙。
    private var selfTintColor: NSColor {
        switch item.kind {
        case .image: return UITheme.success
        case .text: return UITheme.accent
        case .files: return UITheme.warning
        }
    }

    private var typeName: String {
        switch item.kind {
        case .image: return "图片"
        case .text: return "文本"
        case .files: return "文件"
        }
    }

    // MARK: 子视图

    private func buildSubviews(thumbnail: NSImage?, pixelSize: NSSize) {
        // 左上：序号徽章 ⌥N（超出 9 不显示）。
        if let digitLabel = ClipboardDigitKeyCodes.label(for: index) {
            let badge = NSTextField(labelWithString: "\(badgeSymbol)\(digitLabel)")
            badge.font = .systemFont(ofSize: 10, weight: .semibold)
            badge.textColor = UITheme.textSecondary
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.07).cgColor
            badge.layer?.cornerRadius = 5
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            ])
        }

        // 右上：删除 ×（hover 显示）。
        deleteButton.title = "✕"
        deleteButton.isBordered = false
        deleteButton.font = .systemFont(ofSize: 11)
        deleteButton.contentTintColor = UITheme.textSecondary
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.isHidden = true
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deleteButton)

        // 收藏星（可点击切换）。
        let star = NSButton(title: item.isFavorite ? "★" : "☆", target: self, action: #selector(starClicked))
        star.isBordered = false
        star.font = .systemFont(ofSize: 12)
        star.contentTintColor = item.isFavorite ? UITheme.warning : UITheme.textSecondary
        star.translatesAutoresizingMaskIntoConstraints = false
        addSubview(star)

        // 类型徽章（小圆角彩色标签）。
        let typeBadge = NSTextField(labelWithString: typeName)
        typeBadge.font = .systemFont(ofSize: 9, weight: .medium)
        typeBadge.textColor = .white
        typeBadge.wantsLayer = true
        typeBadge.layer?.backgroundColor = selfTintColor.cgColor
        typeBadge.layer?.cornerRadius = 4
        typeBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(typeBadge)

        // 中部内容区。
        let content = buildContentView(thumbnail: thumbnail, pixelSize: pixelSize)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        // 底部信息行。
        let info = NSTextField(labelWithString: infoText)
        info.font = .systemFont(ofSize: 10)
        info.textColor = UITheme.textSecondary
        info.lineBreakMode = .byTruncatingTail
        info.translatesAutoresizingMaskIntoConstraints = false
        addSubview(info)

        NSLayoutConstraint.activate([
            deleteButton.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),

            star.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),
            star.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -2),

            typeBadge.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),
            typeBadge.trailingAnchor.constraint(equalTo: star.leadingAnchor, constant: -4),

            content.topAnchor.constraint(equalTo: topAnchor, constant: 30),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            info.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            info.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            info.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            content.bottomAnchor.constraint(lessThanOrEqualTo: info.topAnchor, constant: -6),
        ])
    }

    /// 内容区：图片 = 等比缩略图（宽撑满、高上限 140）；文本 = 最多 6 行预览；文件 = 文件名列表。
    private func buildContentView(thumbnail: NSImage?, pixelSize: NSSize) -> NSView {
        switch item.kind {
        case .image:
            let imageView = NSImageView()
            imageView.image = thumbnail
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 6
            imageView.layer?.masksToBounds = true
            addSubview(imageView)
            // 缩略图高度按图片宽高比夹在 [44, 140]，小内容顶部对齐、不拉伸占满。
            let thumbSize = ClipboardThumbnail.thumbnailSize(
                pixelWidth: pixelSize.width, pixelHeight: pixelSize.height,
                availableWidth: Self.contentWidth)
            imageView.heightAnchor.constraint(equalToConstant: thumbSize.height).isActive = true
            return imageView
        case .text:
            let field = NSTextField(labelWithString: item.text.replacingOccurrences(of: "\n", with: " ⏎ "))
            field.font = .systemFont(ofSize: 12)
            field.textColor = UITheme.textPrimary
            field.maximumNumberOfLines = 6
            field.lineBreakMode = .byCharWrapping
            field.cell?.wraps = true
            field.toolTip = item.text
            addSubview(field)
            return field
        case .files:
            let names = item.filePaths?.map { ($0 as NSString).lastPathComponent }
                ?? item.text.components(separatedBy: ", ")
            let preview = names.prefix(6).map { "• " + $0 }.joined(separator: "\n")
            let field = NSTextField(labelWithString: preview)
            field.font = .systemFont(ofSize: 12)
            field.textColor = UITheme.textPrimary
            field.maximumNumberOfLines = 6
            field.lineBreakMode = .byTruncatingTail
            field.toolTip = names.joined(separator: "\n")
            addSubview(field)
            return field
        }
    }

    /// 内容区可用宽度（卡宽 - 左右 12 边距）。
    private static var contentWidth: CGFloat { 236 - 12 * 2 }

    /// 底部信息行：相对时间 + 类型补充信息（图片像素尺寸 / 字符数 / 文件数 / KB）。
    private var infoText: String {
        let relative = RelativeTimeFormatter.label(from: item.addedAt, to: Date())
        switch item.kind {
        case .text:
            return "\(relative) · \(item.text.count) 字符"
        case .image:
            let bytes = item.imageData?.count ?? 0
            let kb = max(1, (bytes + 1023) / 1024)
            return "\(relative) · \(item.text) · \(kb) KB"
        case .files:
            return "\(relative) · \(item.filePaths?.count ?? 0) 个文件"
        }
    }

    // MARK: 交互

    /// 点击卡片（按钮区命中时按钮自行处理，不冒泡到卡片）。
    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = UITheme.cardHover.cgColor
        deleteButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = UITheme.cardBackground.cgColor
        if !isArmedForDelete { deleteButton.isHidden = true }
    }

    @objc private func starClicked() {
        onToggleFavorite?()
    }

    /// 两段式删除确认：× → 「确认删除？」（红色）→ 再点执行。
    @objc private func deleteClicked() {
        if !isArmedForDelete {
            isArmedForDelete = true
            deleteButton.attributedTitle = NSAttributedString(
                string: "确认删除",
                attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium),
                             .foregroundColor: UITheme.destructive])
            let work = DispatchWorkItem { [weak self] in self?.disarm() }
            disarmWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
            return
        }
        disarmWorkItem?.cancel()
        onDelete?()
    }

    private func disarm() {
        isArmedForDelete = false
        deleteButton.title = "✕"
        deleteButton.contentTintColor = UITheme.textSecondary
    }
}
