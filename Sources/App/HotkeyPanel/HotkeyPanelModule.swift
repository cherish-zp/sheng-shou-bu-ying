import AppKit

/// 浮引式快捷键面板：虚拟键盘布局的键位绑定总览与直达触发。
/// 窗口模式照 ClipboardHistoryModule：borderless NSPanel + nonactivatingPanel +
/// 流光玻璃 + Esc/失焦关闭 + 底部提示行。
/// 交互：未绑键左键弹绑定菜单（未占用功能 + 搜索应用）；已绑键左键直接触发；
/// 已绑键右键「更换绑定 / 清除绑定」；搜索浮层选中应用后点击键位完成绑定。
/// 应用候选（搜索结果项）：名称 + bundleID。
fileprivate struct AppCandidate {
    let name: String
    let bundleID: String
}

final class HotkeyPanelModule: NSObject {

    /// 面板理想尺寸（小屏按可见区夹持）。
    private static let idealPanelSize = NSSize(width: 1700, height: 600)
    /// 键帽尺寸。
    private static let keyCapSize = NSSize(width: 104, height: 96)

    /// 功能直达执行器（AppDelegate 装配：与全局热键同一动作映射，含启用状态过滤）。
    var functionRunner: ((String) -> Void)?

    private var window: NSPanel?
    private var searchField: NSSearchField?
    private var keyCaps: [Character: HotkeyKeyCapView] = [:]
    private var hintLabel: NSTextField?
    private var resultContainer: NSView?
    private var resultStack: NSStackView?

    /// 正在隐藏面板（orderOut 会触发 didResignKey，用标志避免自我递归关窗）。
    private var isDismissing = false
    private var escMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    /// 搜索浮层选中的应用：等待用户点击键位完成绑定。
    private var pendingApp: AppCandidate?
    /// 已安装应用候选缓存（扫描 /Applications 与 /System/Applications 顶层 .app）。
    private var appCandidates: [AppCandidate] = []
    /// 应用图标缓存（bundleID → 图标）。
    private var appIconCache: [String: NSImage] = [:]

    deinit {
        if let monitor = escMonitor { NSEvent.removeMonitor(monitor) }
        if let observer = resignObserver { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - 显示/隐藏

    func showPanel() {
        if window == nil { buildWindow() }
        guard let panel = window else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        UITheme.center(panel)
        reload()
        window?.makeFirstResponder(searchField)
    }

    func hidePanel() {
        pendingApp = nil
        guard let panel = window, panel.isVisible else { return }
        isDismissing = true
        panel.orderOut(nil)
        isDismissing = false
    }

    // MARK: - 窗口构建

    private func buildWindow() {
        let size = clampedPanelSize()
        let panel = HotkeyPanelWindow(contentRect: NSRect(origin: .zero, size: size),
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
        buildKeyboard(in: content)
        buildHint(in: content)
        buildSearchResults(in: content)
        installDismissHandlers()
    }

    /// 面板尺寸：理想 1700×600，按鼠标所在屏可见区夹持（不小于 900×480）。
    private func clampedPanelSize() -> NSSize {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame.size ?? NSSize(width: 1512, height: 900)
        let width = min(Self.idealPanelSize.width, max(900, visible.width - 40))
        let height = min(Self.idealPanelSize.height, max(480, visible.height - 80))
        return NSSize(width: width, height: height)
    }

    /// 顶栏：App 图标（左）+ 搜索框（中）+ 关闭按钮（右）。
    private func buildTopBar(in content: NSView) {
        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 7
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let search = NSSearchField()
        search.placeholderString = "搜索应用绑定到键位"
        search.font = .systemFont(ofSize: 12)
        search.sendsWholeSearchString = false
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searchChanged)
        search.translatesAutoresizingMaskIntoConstraints = false

        let close = NSButton(title: "✕", target: self, action: #selector(closeClicked))
        close.isBordered = false
        close.contentTintColor = UITheme.textSecondary
        close.font = .systemFont(ofSize: 13, weight: .medium)
        close.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(iconView)
        content.addSubview(search)
        content.addSubview(close)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            search.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            search.centerYAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            search.widthAnchor.constraint(equalToConstant: 320),
            search.heightAnchor.constraint(equalToConstant: 26),

            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            close.centerYAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            close.widthAnchor.constraint(equalToConstant: 24),
        ])
        searchField = search
    }

    /// 键盘区：4 行键帽（数字行 → Q 行 → A 行 → Z 行），外层横向/纵向滚动兜底小屏。
    private func buildKeyboard(in content: NSView) {
        let scroll = NSScrollView()
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let rowsStack = NSStackView()
        rowsStack.orientation = .vertical
        rowsStack.alignment = .centerX
        rowsStack.spacing = 12
        rowsStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        for row in HotkeyPanelLayout.rows {
            let rowStack = NSStackView(views: row.map { makeKeyCap(for: $0) })
            rowStack.orientation = .horizontal
            rowStack.spacing = 12
            rowsStack.addArrangedSubview(rowStack)
        }
        scroll.documentView = rowsStack
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 46),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -26),
            // 滚动文档标准配方：四边钉 contentView + 宽高 ≥ 视口，内容更宽时被撑开出滚动条
            rowsStack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor),
            rowsStack.widthAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor),
            rowsStack.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
        ])
    }

    private func makeKeyCap(for keyChar: Character) -> NSView {
        let view = HotkeyKeyCapView(keyChar: keyChar, cell: .empty(keyLabel: String(keyChar)), icon: nil)
        view.onClick = { [weak self] in self?.keyClicked(keyChar) }
        view.onContext = { [weak self, weak view] in
            guard let self, let view else { return }
            self.keyContextClicked(keyChar, from: view)
        }
        // 键帽无 intrinsic size：必须显式宽高，否则 NSStackView 内塌缩不可见
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: Self.keyCapSize.width),
            view.heightAnchor.constraint(equalToConstant: Self.keyCapSize.height),
        ])
        keyCaps[keyChar] = view
        return view
    }

    /// 底部说明行：快捷键提示（符号随主修饰键变、呼出键随 panelSummon 变）。
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

    /// 搜索结果浮层（搜索框下方浮动列表，点击候选项进入「点键位完成绑定」流程）。
    private func buildSearchResults(in content: NSView) {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 1
        container.layer?.borderColor = UITheme.hairline.cgColor
        container.isHidden = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            container.widthAnchor.constraint(equalToConstant: 320),
        ])
        content.addSubview(container)
        resultContainer = container
        resultStack = stack
    }

    /// 关闭路径：Esc（局部 keyDown 监听，面板可见时消费）+ 失去 key 自动关闭。
    private func installDismissHandlers() {
        guard escMonitor == nil, resignObserver == nil, let panel = window else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true, event.keyCode == 53 else { return event }
            if self.pendingApp != nil {
                self.cancelPendingApp()
                return nil
            }
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
        scanAppsIfNeeded()
        let prefs = HotkeyPreferences.load()
        let appStore = AppLaunchBindingStore.load()
        for (keyChar, view) in keyCaps {
            let cell = HotkeyPanelContent.cell(for: keyChar, prefs: prefs, appStore: appStore)
            let icon: NSImage?
            if case .app(let bundleID, _) = cell {
                icon = self.appIcon(for: bundleID)
            } else {
                icon = nil
            }
            view.update(cell: cell, icon: icon)
        }
        if pendingApp == nil { refreshHint() }
    }

    /// 底部提示：直达热键说明 + 呼出键显示名（F1 → "F1"，字母键 → ⌥X 样式）。
    private func refreshHint() {
        let prefs = HotkeyPreferences.load()
        let symbol = prefs.primaryModifier.symbol
        let summon: String
        if let panel = prefs.panelSummon {
            summon = panel.functionKeyLabel
                ?? (symbol + (Hotkey.letterLabel(for: panel.keyCode) ?? "?"))
        } else {
            summon = "（未设置呼出键）"
        }
        hintLabel?.stringValue =
            "无需打开面板，任意界面按 \(symbol) + 键位 直达已绑定内容 · \(summon) 呼出本面板 · Esc 关闭"
    }

    // MARK: - 键位点击交互

    private func keyClicked(_ keyChar: Character) {
        // 搜索浮层已选应用：点击任意键位完成绑定（覆盖原绑定）
        if let pending = pendingApp {
            bindApp(pending, to: keyChar)
            return
        }
        let cell = HotkeyPanelContent.cell(for: keyChar,
                                           prefs: HotkeyPreferences.load(),
                                           appStore: AppLaunchBindingStore.load())
        switch cell {
        case .function(let id, _, _):
            functionRunner?(id)
        case .app(_, let bundleID):
            launchApp(bundleID: bundleID)
        case .empty:
            if let view = keyCaps[keyChar] {
                showBindingMenu(for: keyChar, from: view)
            }
        }
    }

    private func keyContextClicked(_ keyChar: Character, from view: NSView) {
        let cell = HotkeyPanelContent.cell(for: keyChar,
                                           prefs: HotkeyPreferences.load(),
                                           appStore: AppLaunchBindingStore.load())
        switch cell {
        case .empty:
            showBindingMenu(for: keyChar, from: view)
        case .function, .app:
            showContextMenu(for: keyChar, cell: cell, from: view)
        }
    }

    // MARK: - 绑定菜单（未绑键）

    /// 绑定选择菜单：上半部分未占用该键码的功能，下半部分搜索结果应用（空搜索不列）。
    private func showBindingMenu(for keyChar: Character, from view: NSView) {
        let prefs = HotkeyPreferences.load()
        guard let keyCode = HotkeyPanelKeyCodes.keyCode(for: keyChar) else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let functionTitle = NSMenuItem(title: "绑定功能", action: nil, keyEquivalent: "")
        functionTitle.isEnabled = false
        menu.addItem(functionTitle)
        for entry in HotkeyPreferences.catalog where prefs.bindings[entry.id]?.keyCode != keyCode {
            let item = NSMenuItem(title: entry.title, action: #selector(bindingMenuClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = "func:\(entry.id):\(keyChar)"
            item.isEnabled = true
            menu.addItem(item)
        }

        let text = searchField?.stringValue ?? ""
        let matches = searchApps(text)
        if !matches.isEmpty {
            menu.addItem(.separator())
            let appTitle = NSMenuItem(title: "绑定应用", action: nil, keyEquivalent: "")
            appTitle.isEnabled = false
            menu.addItem(appTitle)
            for candidate in matches.prefix(12) {
                let item = NSMenuItem(title: candidate.name,
                                      action: #selector(bindingMenuClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = "app:\(candidate.bundleID):\(keyChar)"
                item.isEnabled = true
                menu.addItem(item)
            }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
    }

    /// 已绑键右键菜单：更换绑定 / 清除绑定。
    private func showContextMenu(for keyChar: Character,
                                 cell: HotkeyPanelContent.Cell,
                                 from view: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let rebind = NSMenuItem(title: "更换绑定…", action: #selector(bindingMenuClicked(_:)), keyEquivalent: "")
        rebind.target = self
        rebind.representedObject = "rebind:\(keyChar)"
        rebind.isEnabled = true
        menu.addItem(rebind)
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "清除绑定", action: #selector(bindingMenuClicked(_:)), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = true
        switch cell {
        case .function(let id, _, _):
            clear.representedObject = "clearfunc:\(id)"
        case .app(_, let bundleID):
            clear.representedObject = "clearapp:\(bundleID)"
        case .empty:
            return
        }
        menu.addItem(clear)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
    }

    /// 菜单统一入口：representedObject 编码「动作:参数[:键位]」。
    @objc private func bindingMenuClicked(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? String else { return }
        let parts = payload.components(separatedBy: ":")
        guard let action = parts.first else { return }
        switch action {
        case "func":
            guard parts.count == 3, let keyChar = parts[2].first else { return }
            bindFunction(parts[1], to: keyChar)
        case "app":
            guard parts.count == 3, let keyChar = parts[2].first else { return }
            // 应用名取菜单标题（bundleID 不含 ":"，keyChar 在末段）
            bindApp(AppCandidate(name: sender.title, bundleID: parts[1]), to: keyChar)
        case "rebind":
            guard parts.count == 2, let keyChar = parts[1].first,
                  let view = keyCaps[keyChar] else { return }
            showBindingMenu(for: keyChar, from: view)
        case "clearfunc":
            guard parts.count == 2 else { return }
            clearFunctionBinding(id: parts[1])
        case "clearapp":
            guard parts.count == 2 else { return }
            clearAppBinding(bundleID: parts[1])
        default:
            break
        }
    }

    // MARK: - 绑定/清除/触发

    private func bindFunction(_ id: String, to keyChar: Character) {
        guard let keyCode = HotkeyPanelKeyCodes.keyCode(for: keyChar) else { return }
        var prefs = HotkeyPreferences.load()
        prefs.bindings[id] = HotkeyBinding(keyCode: keyCode)
        prefs.save()
        // 同键码的应用绑定让位（一键一动作）
        var store = AppLaunchBindingStore.load()
        if store.binding(forKeyCode: keyCode) != nil {
            store.bindings.removeAll { $0.keyCode == keyCode }
            store.save()
        }
        replayRegistrations()
        reload()
    }

    private func bindApp(_ candidate: AppCandidate, to keyChar: Character) {
        guard let keyCode = HotkeyPanelKeyCodes.keyCode(for: keyChar) else { return }
        var prefs = HotkeyPreferences.load()
        // 键位被功能占用时先移除功能绑定（本次显式选择优先）
        var functionRemoved = false
        for (id, binding) in prefs.bindings where binding.keyCode == keyCode {
            prefs.bindings[id] = nil
            functionRemoved = true
        }
        if functionRemoved { prefs.save() }
        var store = AppLaunchBindingStore.load()
        store.add(AppLaunchBinding(bundleID: candidate.bundleID, name: candidate.name, keyCode: keyCode))
        store.save()
        replayRegistrations()
        cancelPendingApp()
        reload()
    }

    private func clearFunctionBinding(id: String) {
        var prefs = HotkeyPreferences.load()
        guard prefs.bindings[id] != nil else { return }
        prefs.bindings[id] = nil
        prefs.save()
        replayRegistrations()
        reload()
    }

    private func clearAppBinding(bundleID: String) {
        var store = AppLaunchBindingStore.load()
        guard store.bindings.contains(where: { $0.bundleID == bundleID }) else { return }
        store.remove(bundleID: bundleID)
        store.save()
        replayRegistrations()
        reload()
    }

    private func launchApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            DiagLog.write("HotkeyPanel: 找不到应用 \(bundleID)")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    /// 设置改动后全量重放注册（经 AppDelegate，运行时派发，与 HotkeySettingsPaneView 同模式）。
    private static let applyHotkeySelector = NSSelectorFromString("applyHotkeyPreferences")

    private func replayRegistrations() {
        guard let delegate = NSApp.delegate,
              delegate.responds(to: Self.applyHotkeySelector) else { return }
        delegate.perform(Self.applyHotkeySelector)
    }

    // MARK: - 搜索

    @objc private func searchChanged() {
        refreshSearchResults()
    }

    private func refreshSearchResults() {
        guard let stack = resultStack, let container = resultContainer else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let text = searchField?.stringValue ?? ""
        let matches = searchApps(text)
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !matches.isEmpty else {
            container.isHidden = true
            return
        }
        for candidate in matches.prefix(8) {
            let button = HotkeyAppResultButton(title: candidate.name,
                                               target: self, action: #selector(appResultClicked(_:)))
            button.isBordered = false
            button.font = .systemFont(ofSize: 12)
            button.contentTintColor = UITheme.textPrimary
            button.candidate = candidate
            stack.addArrangedSubview(button)
        }
        container.isHidden = false
    }

    @objc private func appResultClicked(_ sender: HotkeyAppResultButton) {
        guard let candidate = sender.candidate else { return }
        pendingApp = candidate
        resultContainer?.isHidden = true
        hintLabel?.stringValue = "已选「\(candidate.name)」——点击一个键位完成绑定（Esc 取消）"
    }

    private func cancelPendingApp() {
        guard pendingApp != nil else { return }
        pendingApp = nil
        resultContainer?.isHidden = true
        refreshHint()
    }

    /// 按名称过滤已安装应用（空查询返回空表）。
    private func searchApps(_ text: String) -> [AppCandidate] {
        scanAppsIfNeeded()
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return appCandidates.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// 扫描 /Applications 与 /System/Applications（含 Utilities）顶层 .app，缓存一次。
    private func scanAppsIfNeeded() {
        guard appCandidates.isEmpty else { return }
        var candidates: [AppCandidate] = []
        var seen = Set<String>()
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
        for root in roots {
            let dirURL = URL(fileURLWithPath: root)
            let items = (try? FileManager.default.contentsOfDirectory(
                at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for item in items where item.pathExtension == "app" {
                guard let bundle = Bundle(url: item), let bundleID = bundle.bundleIdentifier else { continue }
                guard seen.insert(bundleID).inserted else { continue }
                candidates.append(AppCandidate(name: item.deletingPathExtension().lastPathComponent,
                                               bundleID: bundleID))
            }
        }
        appCandidates = candidates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        DiagLog.write("HotkeyPanel: 扫描已安装应用 \(appCandidates.count) 个")
    }

    /// bundleID → 安装图标（缓存）。
    private func appIcon(for bundleID: String) -> NSImage? {
        if let cached = appIconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIconCache[bundleID] = icon
        return icon
    }

    // MARK: - 顶栏动作

    @objc private func closeClicked() {
        hidePanel()
    }
}

// MARK: - 面板窗口（borderless NSPanel，可成为 key 以支持搜索框输入）

final class HotkeyPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - 搜索结果按钮（携带候选项）

final class HotkeyAppResultButton: NSButton {
    fileprivate var candidate: AppCandidate?
}

// MARK: - 键帽视图

/// 单个键帽：约 104×96 圆角 16。已绑功能 = 分类色方块 SF Symbol + 键位角标 + 功能名；
/// 已绑应用 = 应用图标 + 键位角标 + 应用名；未绑 = 中央键位字符 + 「绑定」。
final class HotkeyKeyCapView: NSView {

    let keyChar: Character
    private(set) var cell: HotkeyPanelContent.Cell
    var onClick: (() -> Void)?
    var onContext: (() -> Void)?
    private var hoverArea: NSTrackingArea?

    init(keyChar: Character, cell: HotkeyPanelContent.Cell, icon: NSImage?) {
        self.keyChar = keyChar
        self.cell = cell
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 104, height: 96)))
        wantsLayer = true
        rebuild(icon: icon)
    }

    required init?(coder: NSCoder) { fatalError("不支持 storyboard") }

    func update(cell newCell: HotkeyPanelContent.Cell, icon: NSImage?) {
        guard newCell != cell else { return }
        cell = newCell
        rebuild(icon: icon)
    }

    private func rebuild(icon: NSImage?) {
        subviews.forEach { $0.removeFromSuperview() }
        layer?.backgroundColor = UITheme.cardBackground.cgColor
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = UITheme.hairline.cgColor

        switch cell {
        case .function(let id, let title, let symbolName):
            // 分类色圆角方块 + 白色 SF Symbol
            let box = NSView()
            box.wantsLayer = true
            box.layer?.backgroundColor = UITheme.categoryColor(for: id).cgColor
            box.layer?.cornerRadius = 14
            box.translatesAutoresizingMaskIntoConstraints = false
            addSubview(box)

            let iconView = NSImageView()
            // 系统缺符号时兜底（如 "animated" 部分系统缺失），避免键帽空方块
            let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
                ?? NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: title)
            if let base = symbol {
                iconView.image = base.withSymbolConfiguration(.init(pointSize: 24, weight: .medium))
            }
            iconView.contentTintColor = .white
            iconView.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(iconView)

            let nameLabel = NSTextField(labelWithString: title)
            nameLabel.font = .systemFont(ofSize: 11)
            nameLabel.textColor = UITheme.textPrimary
            nameLabel.alignment = .center
            nameLabel.lineBreakMode = .byTruncatingTail
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(nameLabel)

            let keyBadge = makeKeyBadge()
            addSubview(keyBadge)
            NSLayoutConstraint.activate([
                box.topAnchor.constraint(equalTo: topAnchor, constant: 6),
                box.centerXAnchor.constraint(equalTo: centerXAnchor),
                box.widthAnchor.constraint(equalToConstant: 56),
                box.heightAnchor.constraint(equalToConstant: 56),

                iconView.centerXAnchor.constraint(equalTo: box.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: box.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 30),
                iconView.heightAnchor.constraint(equalToConstant: 30),

                nameLabel.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 4),
                nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),

                keyBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                keyBadge.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: 2),
            ])

        case .app(_, let appName):
            let iconView = NSImageView()
            iconView.image = icon
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconView)

            let nameLabel = NSTextField(labelWithString: appName)
            nameLabel.font = .systemFont(ofSize: 11)
            nameLabel.textColor = UITheme.textPrimary
            nameLabel.alignment = .center
            nameLabel.lineBreakMode = .byTruncatingTail
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(nameLabel)

            let keyBadge = makeKeyBadge()
            addSubview(keyBadge)
            NSLayoutConstraint.activate([
                iconView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
                iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 56),
                iconView.heightAnchor.constraint(equalToConstant: 56),

                nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
                nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),

                keyBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                keyBadge.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 2),
            ])

        case .empty(let keyLabel):
            let bigLabel = NSTextField(labelWithString: keyLabel)
            bigLabel.font = .systemFont(ofSize: 22, weight: .medium)
            bigLabel.textColor = UITheme.textSecondary
            bigLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bigLabel)

            let bindLabel = NSTextField(labelWithString: "绑定")
            bindLabel.font = .systemFont(ofSize: 11)
            bindLabel.textColor = UITheme.textSecondary
            bindLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bindLabel)

            NSLayoutConstraint.activate([
                bigLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                bigLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),
                bindLabel.topAnchor.constraint(equalTo: bigLabel.bottomAnchor, constant: 4),
                bindLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            ])
        }
    }

    /// 键帽右下角键位字符小标。
    private func makeKeyBadge() -> NSTextField {
        let badge = NSTextField(labelWithString: String(keyChar))
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = UITheme.textSecondary
        badge.translatesAutoresizingMaskIntoConstraints = false
        return badge
    }

    // MARK: 交互

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onContext?()
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
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = UITheme.cardBackground.cgColor
    }
}
