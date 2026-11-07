import AppKit

/// 快速片段面板（⌥K 呼出）：流光玻璃悬浮面板，片段横向卡片流——
/// 点击复制 + Toast，hover 删除，搜索过滤，＋新增/右键编辑。
/// 数据层复用 SnippetManager（JSON 持久化 + snippetsDidChange 通知）。
/// 管理入口从设置迁出（用户定案）：本面板即片段的唯一管理界面。
final class SnippetPanelModule: NSObject {

    private var panel: NSPanel?
    private var cardStack: NSStackView?
    private var cardScroll: HorizontalScrollScrollView?
    private var searchField: NSSearchField?
    private var emptyLabel: NSTextField?
    private var editorSheet: NSPanel?
    /// 编辑目标：nil = 新增。
    private var editingSnippetID: UUID?
    private var isDismissing = false
    private var escMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var changeObserver: NSObjectProtocol?

    /// 显示序（key 排序 + 搜索过滤）。
    private var displayed: [Snippet] = []

    func showPanel() {
        if panel == nil { buildWindow() }
        guard let panel else { return }
        positionPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        reload()
    }

    private func hidePanel() {
        closeEditor()
        unregisterHotkeys()
        guard let panel, panel.isVisible else { return }
        isDismissing = true
        panel.orderOut(nil)
        isDismissing = false
    }

    // MARK: - 窗口构建

    private func buildWindow() {
        let panel = ClipboardPanelWindowLike(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 280),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .aqua)
        self.panel = panel

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 880, height: 280))
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
        installDismissHandlers()
        installChangeObserver()
    }

    private func buildTopBar(in content: NSView) {
        let title = NSTextField(labelWithString: "快速片段")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = UITheme.textPrimary
        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)

        let search = NSSearchField()
        search.placeholderString = "搜索片段"
        search.font = .systemFont(ofSize: 12)
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searchChanged)
        search.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(search)

        let add = NSButton(title: "＋", target: self, action: #selector(addClicked))
        add.isBordered = false
        add.font = .systemFont(ofSize: 15, weight: .medium)
        add.contentTintColor = UITheme.accent
        add.toolTip = "新增片段"
        add.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(add)

        let close = NSButton(title: "✕", target: self, action: #selector(closeClicked))
        close.isBordered = false
        close.font = .systemFont(ofSize: 13, weight: .medium)
        close.contentTintColor = UITheme.textSecondary
        close.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(close)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            search.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            search.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            search.widthAnchor.constraint(equalToConstant: 220),
            search.heightAnchor.constraint(equalToConstant: 24),
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 20),
            add.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
            add.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            add.widthAnchor.constraint(equalToConstant: 20),
        ])
        searchField = search
    }

    private func buildCardFlow(in content: NSView) {
        let scroll = HorizontalScrollScrollView()
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
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 40),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor),
        ])
        cardStack = stack
        cardScroll = scroll

        let empty = NSTextField(labelWithString: "暂无片段 · 点右上「＋」新增")
        empty.font = .systemFont(ofSize: 12)
        empty.textColor = UITheme.textSecondary
        empty.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: 10),
        ])
        emptyLabel = empty
    }

    private func positionPanel(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.maxY - size.height - 60)
        panel.setFrameOrigin(origin)
    }

    // MARK: - 刷新

    private func reload() {
        let query = searchField?.stringValue ?? ""
        let all = SnippetManager.shared.snippets
        displayed = query.isEmpty
            ? all.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            : SnippetManager.shared.search(query: query)
        rebuildCards()
        emptyLabel?.isHidden = !displayed.isEmpty
    }

    private func rebuildCards() {
        guard let stack = cardStack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for snippet in displayed {
            let card = SnippetCardView(snippet: snippet)
            card.onCopy = { [weak self] in self?.copySnippet(snippet) }
            card.onDelete = { [weak self] in
                SnippetManager.shared.delete(id: snippet.id)
            }
            card.onEdit = { [weak self] in self?.openEditor(for: snippet) }
            // 先入列再激活约束：与 stack 的约束在 addArrangedSubview 之前激活，
            // 会与 NSStackView 内部约束互斥 abort（中转站/快捷键 pane 同款前科）
            stack.addArrangedSubview(card)
            NSLayoutConstraint.activate([
                card.widthAnchor.constraint(equalToConstant: 200),
                card.topAnchor.constraint(equalTo: stack.topAnchor),
                card.bottomAnchor.constraint(equalTo: stack.bottomAnchor),
            ])
        }
    }

    private func copySnippet(_ snippet: Snippet) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet.content, forType: .string)
        TransientHudToast.show(text: "已复制「\(snippet.key)」")
    }

    // MARK: - 编辑浮层（新增/修改）

    private func openEditor(for snippet: Snippet? = nil) {
        closeEditor()
        editingSnippetID = snippet?.id
        let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 210),
                            styleMask: [.titled, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        sheet.title = snippet == nil ? "新增片段" : "编辑片段"
        sheet.isReleasedWhenClosed = false
        sheet.center()
        sheet.appearance = NSAppearance(named: .aqua)

        let keyField = NSTextField()
        keyField.placeholderString = "片段名（如：ftp下载）"
        keyField.stringValue = snippet?.key ?? ""
        let contentField = NSTextField()
        contentField.placeholderString = "内容"
        contentField.stringValue = snippet?.content ?? ""

        let keyLabel = NSTextField(labelWithString: "名称")
        let contentLabel = NSTextField(labelWithString: "内容")
        for label in [keyLabel, contentLabel] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = UITheme.textSecondary
        }
        let stack = NSStackView(views: [keyLabel, keyField, contentLabel, contentField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        for field in [keyField, contentField] {
            field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        sheet.contentView?.addSubview(stack)

        let save = NSButton(title: "保存", target: self, action: #selector(saveClicked))
        save.keyEquivalent = "\r"
        save.target = self
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelEditorClicked))
        cancel.keyEquivalent = "\u{1b}"
        cancel.target = self
        let buttons = NSStackView(views: [cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        sheet.contentView?.addSubview(buttons)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: sheet.contentView!.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: sheet.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: sheet.contentView!.trailingAnchor, constant: -20),
            buttons.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 14),
            buttons.trailingAnchor.constraint(equalTo: sheet.contentView!.trailingAnchor, constant: -20),
        ])
        editorSheet = sheet
        sheet.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        keyField.becomeFirstResponder()
    }

    @objc private func saveClicked() {
        guard let sheet = editorSheet else { return }
        // sheet contentView 里的两个输入框按顺序取
        let fields = sheet.contentView?.subviews.compactMap { $0 as? NSStackView }.first?.arrangedSubviews
            .compactMap { $0 as? NSTextField } ?? []
        let key = fields.count > 0 ? fields[0].stringValue.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let content = fields.count > 1 ? fields[1].stringValue : ""
        guard !key.isEmpty, !content.isEmpty else {
            TransientHudToast.show(text: "名称与内容都不能为空")
            return
        }
        if let id = editingSnippetID {
            _ = SnippetManager.shared.update(id: id, key: key, content: content)
        } else {
            _ = SnippetManager.shared.add(key: key, content: content)
        }
        closeEditor()
        reload()
    }

    @objc private func cancelEditorClicked() { closeEditor() }

    private func closeEditor() {
        editorSheet?.orderOut(nil)
        editorSheet = nil
        editingSnippetID = nil
    }

    // MARK: - 关闭路径与监听

    private func installDismissHandlers() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isVisible == true, event.keyCode == 53 else { return event }
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

    /// 片段数据变化（编辑保存/删除/菜单栏管理）→ 面板可见时刷新。
    private func installChangeObserver() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .snippetsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.panel?.isVisible == true else { return }
            self.reload()
        }
    }

    private func unregisterHotkeys() {}

    deinit {
        if let monitor = escMonitor { NSEvent.removeMonitor(monitor) }
        if let observer = resignObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = changeObserver { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - 动作

    @objc private func searchChanged() { reload() }
    @objc private func addClicked() { openEditor(for: nil) }
    @objc private func closeClicked() { hidePanel() }
}

/// 面板窗口类型复用（可成为 key 以支持搜索框输入）。
private typealias ClipboardPanelWindowLike = ClipboardPanelWindow

// MARK: - 片段卡片

/// 单个片段卡片：key 名 + 内容预览 + hover 删除，点击复制。
final class SnippetCardView: NSView {

    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?

    private let snippet: Snippet
    private let removeButton = NSButton()
    private var hoverArea: NSTrackingArea?

    init(snippet: Snippet) {
        self.snippet = snippet
        super.init(frame: .zero)
        wantsLayer = true
        UITheme.styleCard(self)
        layer?.cornerRadius = 10

        let keyLabel = NSTextField(labelWithString: snippet.key)
        keyLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        keyLabel.textColor = UITheme.textPrimary
        keyLabel.lineBreakMode = .byTruncatingTail
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyLabel)

        let preview = snippet.content
            .replacingOccurrences(of: "\n", with: " ⏎ ")
        let contentLabel = NSTextField(labelWithString: preview)
        contentLabel.font = .systemFont(ofSize: 10)
        contentLabel.textColor = UITheme.textSecondary
        contentLabel.maximumNumberOfLines = 3
        contentLabel.lineBreakMode = .byCharWrapping
        contentLabel.cell?.wraps = true
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentLabel)

        removeButton.bezelStyle = .texturedRounded
        removeButton.isBordered = false
        let symbol = NSImage(systemSymbolName: "xmark.circle.fill",
                             accessibilityDescription: "删除") ?? NSImage()
        symbol.size = NSSize(width: 13, height: 13)
        removeButton.image = symbol
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.toolTip = "删除片段"
        removeButton.target = self
        removeButton.action = #selector(removeClicked)
        removeButton.isHidden = true
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            keyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            keyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            keyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),

            contentLabel.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 5),
            contentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            removeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])

        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = UITheme.cardHover.cgColor
        removeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = UITheme.cardBackground.cgColor
        removeButton.isHidden = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onEdit?()
        } else {
            onCopy?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let edit = NSMenuItem(title: "编辑", action: #selector(editClicked), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        let remove = NSMenuItem(title: "删除", action: #selector(removeClicked), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        return menu
    }

    @objc private func removeClicked() { onDelete?() }
    @objc private func editClicked() { onEdit?() }
}
