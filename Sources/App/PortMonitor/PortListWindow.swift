import AppKit

/// 端口占用窗口：表格（端口/协议/PID/进程/状态/操作）+ 工具条（刷新/搜索/仅监听切换）
/// + 底部详情条（选中行完整地址）。数据经 PortQueryService（lsof），终止经 PortKillService。
final class PortListWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {

    private let queryService: PortQueryService
    private let killService: PortKillService
    let window: NSWindow

    private var allEntries: [PortProcessEntry] = []
    /// 防御：迟到回调（已发起新一轮查询）不覆盖新数据。
    private var queryGeneration = 0
    private var filter = PortListFilter() {
        didSet { reloadFiltered() }
    }
    private var isQuerying = false {
        didSet { refreshButton.isEnabled = !isQuerying }
    }

    // MARK: - UI

    private var tableView: NSTableView!
    private var searchField: NSSearchField!
    private var listenToggle: NSSegmentedControl!
    private var refreshButton: NSButton!
    private var statusLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var emptyLabel: NSTextField!
    private var filteredEntries: [PortProcessEntry] = []

    init(queryService: PortQueryService, killService: PortKillService) {
        self.queryService = queryService
        self.killService = killService

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init()

        window.title = "端口占用"
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 780, height: 500))
        window.contentView = content
        content.autoresizingMask = [.width, .height]
        buildLayout(in: content)
        window.delegate = self
    }

    func showAndRefresh() {
        window.makeKeyAndOrderFront(nil)
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        // 关闭仅 orderOut（isReleasedWhenClosed=false），控制器与数据保留供再次呼出
    }

    // MARK: - 布局

    private func buildLayout(in content: NSView) {
        // 工具条
        refreshButton = NSButton(title: "刷新", target: self, action: #selector(refreshClicked))
        refreshButton.bezelStyle = .rounded
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(refreshButton)

        listenToggle = NSSegmentedControl(labels: ["仅监听", "全部连接"],
                                          trackingMode: .selectOne, target: self,
                                          action: #selector(modeChanged))
        listenToggle.selectedSegment = 0
        listenToggle.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(listenToggle)

        searchField = NSSearchField()
        searchField.placeholderString = "搜索进程名 / 端口 / PID"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(searchField)

        // 表格
        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 30
        tableView.allowsColumnResizing = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        for (title, width) in [("端口", 80.0), ("协议", 60.0), ("PID", 70.0),
                               ("进程", 150.0), ("状态", 120.0), ("操作", 90.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
            column.title = title
            column.width = width
            column.minWidth = 50
            tableView.addTableColumn(column)
        }

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        // 空态
        emptyLabel = NSTextField(labelWithString: "无端口占用")
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(emptyLabel)
        detailLabel = NSTextField(labelWithString: " ")
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(detailLabel)

        statusLabel = NSTextField(labelWithString: " ")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            refreshButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            refreshButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            listenToggle.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            listenToggle.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 10),
            searchField.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            searchField.leadingAnchor.constraint(greaterThanOrEqualTo: listenToggle.trailingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),

            scroll.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            detailLabel.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            detailLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -10),
            statusLabel.centerYAnchor.constraint(equalTo: detailLabel.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            detailLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
    }

    // MARK: - 动作

    @objc private func refreshClicked() { refresh() }

    @objc private func modeChanged() {
        filter.listenOnly = listenToggle.selectedSegment == 0
    }

    /// 查询（后台 lsof → 主线程解析）。打开窗口与手动刷新共用。
    func refresh() {
        guard !isQuerying else { return }
        isQuerying = true
        queryGeneration += 1
        let generation = queryGeneration
        statusLabel.stringValue = "查询中…"
        queryService.query(mode: filter.listenOnly ? .listening : .all) { [weak self] result in
            guard let self = self, generation == self.queryGeneration else { return }
            self.isQuerying = false
            switch result {
            case .success(let entries):
                self.allEntries = entries.sorted { $0.port < $1.port }
                self.reloadFiltered()
            case .failure(let error):
                self.allEntries = []
                self.reloadFiltered()
                self.statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    private func reloadFiltered() {
        filteredEntries = filter.apply(allEntries)
        tableView.reloadData()
        emptyLabel.isHidden = !filteredEntries.isEmpty
        emptyLabel.stringValue = allEntries.isEmpty ? "无端口占用" : "无匹配结果"
        let modeText = filter.listenOnly ? "仅监听" : "全部连接"
        if allEntries.isEmpty {
            statusLabel.stringValue = "\(modeText) · 共 0 条"
        } else {
            statusLabel.stringValue = "\(modeText) · 共 \(filteredEntries.count) 条（总 \(allEntries.count)）"
        }
        if filteredEntries.isEmpty {
            detailLabel.stringValue = " "
        }
    }

    // MARK: - 结束进程

    private func confirmAndKill(_ entry: PortProcessEntry) {
        let alert = NSAlert()
        alert.messageText = "结束进程？"
        alert.informativeText = "\(entry.processName)（PID \(entry.pid)）占用端口 \(entry.port)，结束其进程？"
        alert.addButton(withTitle: "结束")
        alert.addButton(withTitle: "取消")
        if alert.runModal() != .alertFirstButtonReturn { return }
        statusLabel.stringValue = "正在结束 \(entry.processName)（PID \(entry.pid)）…"
        killService.kill(entry: entry) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.refresh()
            case .failure(let error):
                self.statusLabel.stringValue = "结束失败：\(error.localizedDescription)"
                let alert = NSAlert()
                alert.messageText = "无法结束进程"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { filteredEntries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filteredEntries[row]
        let identifier = tableColumn?.identifier.rawValue ?? ""

        if identifier == "操作" {
            let button = NSButton(title: "结束", target: self, action: #selector(killClicked(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.tag = row
            button.isEnabled = entry.isCurrentUser
            button.toolTip = entry.isCurrentUser ? "结束该进程（SIGTERM → 2 秒后 SIGKILL）" : "非当前用户进程，需 root"
            return button
        }

        let text: String
        switch identifier {
        case "端口": text = "\(entry.port)"
        case "协议": text = entry.protocolName
        case "PID": text = "\(entry.pid)"
        case "进程": text = entry.processName
        case "状态": text = entry.state.isEmpty ? "—" : entry.state
        default: text = ""
        }
        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("cell"), owner: nil) as? NSTableCellView
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
        cell.textField?.textColor = entry.isCurrentUser ? .labelColor : .secondaryLabelColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredEntries.count else {
            detailLabel.stringValue = " "
            return
        }
        let entry = filteredEntries[row]
        detailLabel.stringValue = "PID \(entry.pid) · \(entry.processName) · \(entry.user)\(entry.isCurrentUser ? "" : "（非当前用户）") · \(entry.address)\(entry.state.isEmpty ? "" : " · \(entry.state)")"
    }

    @objc private func killClicked(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < filteredEntries.count else { return }
        confirmAndKill(filteredEntries[row])
    }
}

// MARK: - 搜索回调

extension PortListWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        filter.searchText = searchField.stringValue
    }
}
