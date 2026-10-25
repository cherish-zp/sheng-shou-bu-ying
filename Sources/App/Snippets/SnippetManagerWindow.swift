import AppKit

/// 片段管理视图：master-detail（Apple 系统设置语言）——左侧系统高亮列表 + ＋/－ 工具条，
/// 右侧灰标签表单；编辑自动保存（防抖 400ms，⌘S 立即），双击列表条目复制。
final class SnippetManagerView: NSView, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {

    private let manager = SnippetManager.shared
    private var tableView: NSTableView!
    private var searchField: NSSearchField!
    private var keyField: NSTextField!
    private var contentField: NSTextView!
    private var selectedSnippet: Snippet?
    private var filteredSnippets: [Snippet] = []
    private var emptyStateLabel: NSTextField!
    private var minusButton: NSButton!
    /// 自动保存防抖（编辑即存，无需保存按钮）。
    private var autosaveWorkItem: DispatchWorkItem?

    var onSnippetActivated: (() -> Void)?
    let undoableFieldEditor = UndoFieldEditorPolicy.makeFieldEditor()

    private static let cellID = NSUserInterfaceItemIdentifier("snippetCell")

    init() {
        super.init(frame: .zero)
        buildUI()
        reloadTable()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    /// ⌘S 立即保存（自动保存之外的兜底习惯键）。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "s" {
            saveNow(manual: true)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - UI 构建

    private func buildUI() {
        let bg = NSVisualEffectView()
        bg.material = .windowBackground
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bg)

        // —— 左列：搜索 + 系统高亮列表 + ＋/－ 工具条（系统设置语言，无卡片包装）——
        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "搜索片段…"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self
        bg.addSubview(searchField)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClicked)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        // 行高 52：两行（key 13pt + 预览 11pt）+ 6/4 边距 ≈ 42，留足余量——
        // 44 时约束过约束（48>44），autolayout 打破哪条因环境而异，真实表格里
        // 表现为预览行被压扁、字只见上半截。
        tableView.rowHeight = 52
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("snippet"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        scrollView.documentView = tableView
        bg.addSubview(scrollView)

        emptyStateLabel = NSTextField(labelWithString: "")
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = .systemFont(ofSize: 12)
        emptyStateLabel.textColor = .tertiaryLabelColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.maximumNumberOfLines = 2
        bg.addSubview(emptyStateLabel)

        let plusButton = makeToolbarButton(symbol: "plus", action: #selector(addClicked))
        minusButton = makeToolbarButton(symbol: "minus", action: #selector(deleteClicked))
        let toolbar = NSStackView(views: [plusButton, minusButton])
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(toolbar)

        // —— 右列：灰小标签 + 系统输入框（系统设置表单语言）——
        let keyLabel = makeCaption("Key")
        bg.addSubview(keyLabel)
        keyField = NSTextField()
        keyField.translatesAutoresizingMaskIntoConstraints = false
        keyField.placeholderString = "输入 key（唯一标识）"
        keyField.font = .systemFont(ofSize: 13)
        keyField.delegate = self
        bg.addSubview(keyField)

        let contentLabel = makeCaption("内容")
        bg.addSubview(contentLabel)

        let editorBox = NSView()
        editorBox.wantsLayer = true
        editorBox.layer?.cornerRadius = 6
        editorBox.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        editorBox.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        editorBox.layer?.borderWidth = 1
        editorBox.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(editorBox)

        let contentScroll = NSScrollView()
        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.hasVerticalScroller = true
        contentScroll.borderType = .noBorder
        contentScroll.drawsBackground = false
        contentField = NSTextView()
        contentField.isEditable = true
        contentField.isRichText = false
        contentField.allowsUndo = true
        contentField.delegate = self
        contentField.font = .systemFont(ofSize: 13)
        contentField.backgroundColor = .clear
        contentField.autoresizingMask = [.width]
        contentField.textContainerInset = NSSize(width: 8, height: 8)
        contentField.textContainer?.widthTracksTextView = true
        contentScroll.documentView = contentField
        editorBox.addSubview(contentScroll)

        let pad: CGFloat = 20
        let listWidth: CGFloat = 232
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: trailingAnchor),
            bg.topAnchor.constraint(equalTo: topAnchor),
            bg.bottomAnchor.constraint(equalTo: bottomAnchor),

            searchField.topAnchor.constraint(equalTo: bg.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: pad),
            searchField.widthAnchor.constraint(equalToConstant: listWidth),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            scrollView.widthAnchor.constraint(equalToConstant: listWidth),
            scrollView.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -8),

            emptyStateLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 12),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -12),

            toolbar.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -16),

            keyLabel.topAnchor.constraint(equalTo: bg.topAnchor, constant: 20),
            keyLabel.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 28),
            keyLabel.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -pad),

            keyField.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 6),
            keyField.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            keyField.trailingAnchor.constraint(equalTo: keyLabel.trailingAnchor),

            contentLabel.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 18),
            contentLabel.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            contentLabel.trailingAnchor.constraint(equalTo: keyLabel.trailingAnchor),

            editorBox.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 6),
            editorBox.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            editorBox.trailingAnchor.constraint(equalTo: keyLabel.trailingAnchor),
            editorBox.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -pad),

            contentScroll.topAnchor.constraint(equalTo: editorBox.topAnchor),
            contentScroll.leadingAnchor.constraint(equalTo: editorBox.leadingAnchor),
            contentScroll.trailingAnchor.constraint(equalTo: editorBox.trailingAnchor),
            contentScroll.bottomAnchor.constraint(equalTo: editorBox.bottomAnchor),
        ])

        updateButtonStates()
        updateEmptyState()
    }

    // MARK: - UI 辅助

    private func makeCaption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// 系统设置式小图标按钮（＋/－）。
    private func makeToolbarButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)
        image?.isTemplate = true
        button.image = image
        button.isBordered = true
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    // MARK: - 数据

    func reloadTable() {
        let query = searchField.stringValue
        filteredSnippets = query.isEmpty ? manager.snippets : manager.search(query: query)
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        if manager.snippets.isEmpty {
            emptyStateLabel.stringValue = "暂无片段\n点按 ＋ 新增"
            emptyStateLabel.isHidden = false
        } else if filteredSnippets.isEmpty {
            emptyStateLabel.stringValue = "未找到匹配的片段"
            emptyStateLabel.isHidden = false
        } else {
            emptyStateLabel.isHidden = true
        }
    }

    private func updateButtonStates() {
        minusButton.isEnabled = selectedSnippet != nil
    }

    // MARK: - 搜索与自动保存

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === searchField {
            reloadTable()
            return
        }
        if obj.object as? NSTextField === keyField {
            scheduleAutosave()
        }
    }

    func textDidChange(_ notification: Notification) {
        if notification.object as? NSTextView === contentField {
            scheduleAutosave()
        }
    }

    /// 编辑防抖自动保存（400ms 静默后落盘；⌘S 走 saveNow 立即）。
    private func scheduleAutosave() {
        autosaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveNow(manual: false)
        }
        autosaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    // MARK: - 操作

    @objc private func addClicked() {
        tableView.deselectAll(nil)
        selectedSnippet = nil
        keyField.stringValue = ""
        contentField.string = ""
        updateButtonStates()
        keyField.becomeFirstResponder()
    }

    @objc private func deleteClicked() {
        guard let snippet = selectedSnippet else { return }
        manager.delete(id: snippet.id)
        selectedSnippet = nil
        keyField.stringValue = ""
        contentField.string = ""
        reloadTable()
        updateButtonStates()
    }

    /// 保存：新建或更新。manual = ⌘S（空 key 提示）；自动保存空 key 静默跳过。
    private func saveNow(manual: Bool) {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = contentField.string
        guard !key.isEmpty || selectedSnippet != nil else {
            if manual { NSSound.beep() }
            return
        }
        guard !key.isEmpty else {
            if manual { NSSound.beep() }
            return
        }
        if let snippet = selectedSnippet {
            if !manager.update(id: snippet.id, key: key, content: content) {
                if manual { NSSound.beep() }
            }
        } else if let added = manager.add(key: key, content: content) {
            selectedSnippet = added
            updateButtonStates()
        } else if manual {
            NSSound.beep()
        }
        reloadTable()
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredSnippets.count,
              manager.copyToPasteboard(forKey: filteredSnippets[row].key) else { return }
        onSnippetActivated?()
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredSnippets.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let snippet = filteredSnippets[row]
        let cell = tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? SnippetCellView
            ?? SnippetCellView()
        cell.identifier = Self.cellID
        cell.configure(key: snippet.key, content: snippet.content)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredSnippets.count else {
            selectedSnippet = nil
            updateButtonStates()
            return
        }
        // 切换选中即落盘上一条的防抖编辑
        autosaveWorkItem?.cancel()
        saveNow(manual: false)
        let snippet = filteredSnippets[row]
        selectedSnippet = snippet
        keyField.stringValue = snippet.key
        contentField.string = snippet.content
        updateButtonStates()
    }
}

/// 片段管理独立窗口，保留给后续快捷入口复用。
final class SnippetManagerWindow: NSWindow, NSWindowDelegate {
    private let managerView = SnippetManagerView()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "管理片段"
        titlebarAppearsTransparent = true
        center()
        isReleasedWhenClosed = false
        minSize = NSSize(width: 660, height: 420)
        delegate = self
        contentView = managerView
    }

    func showAndFocus() {
        managerView.reloadTable()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        managerView.undoableFieldEditor
    }
}

// MARK: - 列表单元格

final class SnippetCellView: NSTableCellView {

    private let keyLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        keyLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        keyLabel.textColor = .labelColor
        keyLabel.lineBreakMode = .byTruncatingTail
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyLabel)

        previewLabel.font = .systemFont(ofSize: 11)
        previewLabel.textColor = .tertiaryLabelColor
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.maximumNumberOfLines = 1
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewLabel)

        NSLayoutConstraint.activate([
            keyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            keyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            keyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            previewLabel.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 2),
            previewLabel.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            previewLabel.trailingAnchor.constraint(equalTo: keyLabel.trailingAnchor),
            previewLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(key: String, content: String) {
        keyLabel.stringValue = key
        let preview = content.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        previewLabel.stringValue = preview.isEmpty ? "（空内容）" : preview
    }
}
