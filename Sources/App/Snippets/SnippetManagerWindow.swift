import AppKit

/// 片段管理视图：master-detail 布局，可独立成窗口，也可嵌入设置页。
final class SnippetManagerView: NSView, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {

    private let manager = SnippetManager.shared
    private var tableView: NSTableView!
    private var searchField: NSSearchField!
    private var keyField: NSTextField!
    private var contentField: NSTextView!
    private var selectedSnippet: Snippet?
    private var filteredSnippets: [Snippet] = []
    private var emptyStateLabel: NSTextField!
    private var copyButton: NSButton!
    private var deleteButton: NSButton!

    var onSnippetActivated: (() -> Void)?
    let undoableFieldEditor = UndoFieldEditorPolicy.makeFieldEditor()

    private static let cellID = NSUserInterfaceItemIdentifier("snippetCell")

    init() {
        super.init(frame: .zero)
        buildUI()
        reloadTable()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    // MARK: - UI 构建

    private func buildUI() {
        let bg = NSVisualEffectView()
        bg.material = .windowBackground
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bg)

        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "搜索片段…"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self
        bg.addSubview(searchField)

        let listCard = makeCard()
        let listContent = listCard.contentView!
        bg.addSubview(listCard)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClicked)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 54
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("snippet"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        scrollView.documentView = tableView
        listContent.addSubview(scrollView)

        emptyStateLabel = NSTextField(labelWithString: "")
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = .systemFont(ofSize: 12)
        emptyStateLabel.textColor = .tertiaryLabelColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.cell?.truncatesLastVisibleLine = false
        emptyStateLabel.cell?.wraps = true
        emptyStateLabel.maximumNumberOfLines = 2
        listContent.addSubview(emptyStateLabel)

        let detailCard = makeCard()
        let detailContent = detailCard.contentView!
        bg.addSubview(detailCard)

        let keyLabel = makeCaption("Key")
        detailContent.addSubview(keyLabel)

        keyField = NSTextField()
        keyField.translatesAutoresizingMaskIntoConstraints = false
        keyField.placeholderString = "输入 key（唯一标识）"
        keyField.font = .systemFont(ofSize: 13)
        keyField.delegate = self
        detailContent.addSubview(keyField)

        let contentLabel = makeCaption("内容")
        detailContent.addSubview(contentLabel)

        let contentScroll = NSScrollView()
        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.hasVerticalScroller = true
        contentScroll.borderType = .noBorder
        contentScroll.drawsBackground = false
        contentField = NSTextView()
        contentField.isEditable = true
        contentField.isRichText = false
        contentField.allowsUndo = true
        contentField.font = .systemFont(ofSize: 13)
        contentField.backgroundColor = .clear
        contentField.autoresizingMask = [.width]
        contentField.textContainerInset = NSSize(width: 6, height: 6)
        contentField.textContainer?.widthTracksTextView = true
        contentScroll.documentView = contentField
        detailContent.addSubview(contentScroll)

        let addButton = makeButton(symbol: "plus", label: "新增", action: #selector(addClicked))
        deleteButton = makeButton(symbol: "minus", label: "删除", action: #selector(deleteClicked))
        copyButton = makeButton(symbol: "doc.on.doc", label: "复制", action: #selector(copyClicked))
        let saveButton = makeButton(symbol: "checkmark", label: "保存", action: #selector(saveClicked), accent: true)
        saveButton.keyEquivalent = "\r"

        let leftButtons = NSStackView(views: [addButton, deleteButton, copyButton])
        leftButtons.orientation = .horizontal
        leftButtons.spacing = 8
        leftButtons.translatesAutoresizingMaskIntoConstraints = false
        detailContent.addSubview(leftButtons)

        saveButton.translatesAutoresizingMaskIntoConstraints = false
        detailContent.addSubview(saveButton)

        let pad: CGFloat = 16
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: trailingAnchor),
            bg.topAnchor.constraint(equalTo: topAnchor),
            bg.bottomAnchor.constraint(equalTo: bottomAnchor),

            searchField.topAnchor.constraint(equalTo: bg.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: pad),
            searchField.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -pad),
            searchField.heightAnchor.constraint(equalToConstant: 28),

            listCard.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            listCard.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: pad),
            listCard.widthAnchor.constraint(equalToConstant: 270),
            listCard.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -pad),

            scrollView.topAnchor.constraint(equalTo: listContent.topAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: listContent.leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: listContent.trailingAnchor, constant: -6),
            scrollView.bottomAnchor.constraint(equalTo: listContent.bottomAnchor, constant: -6),

            emptyStateLabel.centerXAnchor.constraint(equalTo: listContent.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: listContent.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: listContent.leadingAnchor, constant: 12),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: listContent.trailingAnchor, constant: -12),

            detailCard.topAnchor.constraint(equalTo: listCard.topAnchor),
            detailCard.leadingAnchor.constraint(equalTo: listCard.trailingAnchor, constant: 12),
            detailCard.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -pad),
            detailCard.bottomAnchor.constraint(equalTo: listCard.bottomAnchor),

            keyLabel.topAnchor.constraint(equalTo: detailContent.topAnchor, constant: pad),
            keyLabel.leadingAnchor.constraint(equalTo: detailContent.leadingAnchor, constant: pad),
            keyLabel.trailingAnchor.constraint(equalTo: detailContent.trailingAnchor, constant: -pad),

            keyField.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 6),
            keyField.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            keyField.trailingAnchor.constraint(equalTo: keyLabel.trailingAnchor),

            contentLabel.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 14),
            contentLabel.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            contentLabel.trailingAnchor.constraint(equalTo: keyLabel.trailingAnchor),

            contentScroll.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 6),
            contentScroll.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            contentScroll.trailingAnchor.constraint(equalTo: keyLabel.trailingAnchor),
            contentScroll.bottomAnchor.constraint(equalTo: leftButtons.topAnchor, constant: -14),

            leftButtons.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            leftButtons.bottomAnchor.constraint(equalTo: detailContent.bottomAnchor, constant: -pad),

            saveButton.trailingAnchor.constraint(equalTo: keyLabel.trailingAnchor),
            saveButton.bottomAnchor.constraint(equalTo: detailContent.bottomAnchor, constant: -pad),
        ])

        updateButtonStates()
        updateEmptyState()
    }

    // MARK: - UI 辅助

    private func makeCard() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 12
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35)
        box.contentViewMargins = NSSize(width: 0, height: 0)
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func makeCaption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeButton(symbol: String, label: String, action: Selector, accent: Bool = false) -> NSButton {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = label
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageLeading
        button.target = self
        button.action = action
        button.bezelStyle = accent ? .rounded : .recessed
        button.contentTintColor = accent ? .controlAccentColor : .secondaryLabelColor
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
            emptyStateLabel.stringValue = "暂无片段\n点击「+ 新增」创建"
            emptyStateLabel.isHidden = false
        } else if filteredSnippets.isEmpty {
            emptyStateLabel.stringValue = "未找到匹配的片段"
            emptyStateLabel.isHidden = false
        } else {
            emptyStateLabel.isHidden = true
        }
    }

    private func updateButtonStates() {
        let hasSelection = selectedSnippet != nil
        copyButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
    }

    // MARK: - 搜索

    func controlTextDidChange(_ object: Notification) {
        guard object.object as? NSSearchField === searchField else { return }
        reloadTable()
    }

    // MARK: - 按钮操作

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

    @objc private func saveClicked() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = contentField.string
        guard !key.isEmpty else {
            NSSound.beep()
            return
        }
        if let snippet = selectedSnippet {
            if !manager.update(id: snippet.id, key: key, content: content) {
                NSSound.beep()
            }
        } else {
            if let added = manager.add(key: key, content: content) {
                selectedSnippet = added
            } else {
                NSSound.beep()
            }
        }
        reloadTable()
        updateButtonStates()
    }

    @objc private func copyClicked() {
        guard let snippet = selectedSnippet else { return }
        _ = manager.copyToPasteboard(forKey: snippet.key)
        flashCopyButton()
    }

    private func flashCopyButton() {
        let originalTitle = copyButton.title
        let originalImage = copyButton.image
        copyButton.title = "已复制"
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "已复制")
        copyButton.contentTintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.title = originalTitle
            self?.copyButton.image = originalImage
            self?.copyButton.contentTintColor = .secondaryLabelColor
        }
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

private final class SnippetCellView: NSTableCellView {

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
            keyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            keyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            keyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            previewLabel.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 2),
            previewLabel.leadingAnchor.constraint(equalTo: keyLabel.leadingAnchor),
            previewLabel.trailingAnchor.constraint(equalTo: keyLabel.trailingAnchor),
            previewLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(key: String, content: String) {
        keyLabel.stringValue = key
        let preview = content.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        previewLabel.stringValue = preview.isEmpty ? "（空内容）" : preview
    }
}
