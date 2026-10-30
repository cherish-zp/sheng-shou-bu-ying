import AppKit

/// 剪贴板历史：1 秒轮询 changeCount 捕获变更（文本/图片/文件），持久化到
/// App Support；深色窗口展示，点击条目回写剪贴板，星标收藏置顶。
final class ClipboardHistoryModule: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    let id = "clipboardHistory"
    let title = "剪贴板历史"

    private let storageURL: URL
    private var store = ClipboardHistoryStore()
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var pollTimer: Timer?
    private var window: NSWindow?
    private var tableView: NSTableView?
    private var displayed: [ClipboardHistoryItem] = []

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

    func start() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        window?.orderOut(nil)
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
        reload()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    // MARK: - 窗口

    func showWindow() {
        if window == nil { buildWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        reload()
    }

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "剪贴板历史"
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 460))
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        UITheme.stylePanel(content)

        let table = NSTableView()
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 34
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = 490
        table.addTableColumn(column)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        tableView = table

        let hint = NSTextField(labelWithString: "点击回写剪贴板 · 星标收藏置顶")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = UITheme.textSecondary
        hint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hint)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -8),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
    }

    private func reload() {
        displayed = store.displayOrder
        tableView?.reloadData()
    }

    // MARK: - 表格

    func numberOfRows(in tableView: NSTableView) -> Int { displayed.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = displayed[row]

        if tableColumn?.identifier.rawValue == "star" {
            let button = NSButton(title: item.isFavorite ? "★" : "☆", target: self,
                                  action: #selector(toggleFavorite(_:)))
            button.isBordered = false
            button.tag = row
            return button
        }

        let prefix: String
        switch item.kind {
        case .text: prefix = ""
        case .image: prefix = "🖼 "
        case .files: prefix = "📁 "
        }
        let text = prefix + item.text.replacingOccurrences(of: "\n", with: " ⏎ ")
        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("clip-cell"), owner: nil) as? NSTableCellView
            ?? {
                let cell = NSTableCellView()
                let field = NSTextField(labelWithString: "")
                field.lineBreakMode = .byTruncatingTail
                field.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(field)
                cell.textField = field
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
                return cell
            }()
        cell.textField?.stringValue = text
        cell.textField?.textColor = item.isFavorite ? UITheme.warning : UITheme.textPrimary
        cell.toolTip = text
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView?.selectedRow ?? -1
        guard row >= 0, row < displayed.count else { return }
        let item = displayed[row]
        let board = NSPasteboard.general
        board.clearContents()
        if let data = item.imageData, let image = NSImage(data: data) {
            board.writeObjects([image])
        } else if let paths = item.filePaths {
            board.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
        } else {
            board.setString(item.text, forType: .string)
        }
        statusFlash(item.text)
        tableView?.deselectRow(row)
    }

    private func statusFlash(_ text: String) {
        guard let content = window?.contentView else { return }
        let flash = existingOrNewFlash(in: content)
        flash.stringValue = "已回写剪贴板：\(text.prefix(40))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak flash] in
            flash?.stringValue = " "
        }
    }

    private weak var flashLabel: NSTextField?
    private func existingOrNewFlash(in content: NSView) -> NSTextField {
        if let flashLabel = flashLabel { return flashLabel }
        let flash = NSTextField(labelWithString: " ")
        flash.font = .systemFont(ofSize: 11)
        flash.textColor = UITheme.success
        flash.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(flash)
        NSLayoutConstraint.activate([
            flash.centerYAnchor.constraint(equalTo: content.subviews.last!.centerYAnchor),
            flash.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
        ])
        flashLabel = flash
        return flash
    }

    @objc private func toggleFavorite(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < displayed.count else { return }
        store.toggleFavorite(id: displayed[row].id)
        persist()
        reload()
    }
}
