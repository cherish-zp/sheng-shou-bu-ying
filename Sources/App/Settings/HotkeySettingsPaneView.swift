import AppKit

/// 快捷键设置面板：主修饰键切换（⌥/⌃/⌘）+ 13 个功能行（录制组合键 / 清除绑定）
/// + 冲突即时红字提示 + 注册失败警告条。流光主题（玻璃垫底、透明分组框）。
/// 录制交互：点击行内按钮进入录制态 → 本地事件监视器捕获 keyDown（Esc 取消、
/// 纯修饰键忽略、其他键入候选绑定，⇧ 可叠加）；点击任意处结束录制。
final class HotkeySettingsPaneView: NSView {

    /// 内存中的快捷键方案：所有改动先落这里，无冲突/清除时才 save + 重放注册。
    private var prefs: HotkeyPreferences
    /// 录制目标：功能组合键（主修饰键 + 单键）或面板呼出键（无主修饰键语义）；nil = 未在录制。
    private enum RecordingTarget {
        case function(String)
        case panelSummon
    }
    private var recordingTarget: RecordingTarget?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    private var modifierControl: NSSegmentedControl!
    private var summonButton: NSButton!
    /// 功能 id → 组合键按钮（refreshLabel/录制态经此更新；漏存会导致按钮文案恒空）
    private var bindingButtons: [String: NSButton] = [:]
    private var conflictLabel: NSTextField!
    private var failureLabel: NSTextField!
    /// 内容滚动区：窗口拉大后夹持滚动原点（防止旧原点残留把内容推下去形成顶部空白）
    private var scrollArea: NSScrollView?

    init() {
        prefs = HotkeyPreferences.load()
        super.init(frame: .zero)
        buildUI()
        refreshAllLabels()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    deinit {
        removeRecordingMonitors()
    }

    // MARK: - UI 构建

    private func buildUI() {
        let titleLabel = NSTextField(labelWithString: "快捷键")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = UITheme.textPrimary

        let hintLabel = NSTextField(
            labelWithString: "组合键 = 主修饰键 + 单键（可叠加 ⇧）。点击功能行右侧按钮后按下新组合键：⎋ 取消，点击任意处结束。面板呼出键无主修饰键（功能键直接按即呼出）。")
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = UITheme.textSecondary
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 3

        // 主修饰键：切换后全量重放注册（所有功能热键一起变）
        modifierControl = NSSegmentedControl(
            labels: PrimaryModifier.allCases.map { $0.displayName },
            trackingMode: .selectOne, target: self, action: #selector(modifierChanged(_:)))
        modifierControl.selectedSegment = PrimaryModifier.allCases.firstIndex(of: prefs.primaryModifier) ?? 0
        let modifierRow = makeRow(label: "全局主修饰键", controls: [modifierControl])

        // 面板呼出键：录制后无主修饰键直接注册（默认 F1）
        summonButton = NSButton(title: "", target: self, action: #selector(summonClicked))
        summonButton.bezelStyle = .rounded
        summonButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        let summonClear = NSButton(title: "×", target: self, action: #selector(clearSummonClicked))
        summonClear.isBordered = false
        summonClear.toolTip = "清除面板呼出键"
        summonClear.translatesAutoresizingMaskIntoConstraints = false
        summonClear.widthAnchor.constraint(equalToConstant: 20).isActive = true
        let summonRow = makeRow(label: "面板呼出键（快捷键面板）", controls: [summonButton, summonClear])

        let modifierContent = NSStackView(views: [modifierRow, summonRow])
        modifierContent.orientation = .vertical
        modifierContent.alignment = .leading
        modifierContent.spacing = 8
        let modifierBox = makeGroupBox(title: "主修饰键", content: modifierContent)

        // 13 个功能行：分类色圆点 + 功能名 + 组合键按钮 + × 清除
        var rows: [NSView] = []
        for entry in HotkeyPreferences.catalog {
            rows.append(makeFunctionRow(entry))
        }
        let rowsStack = NSStackView(views: rows)
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 6
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        for row in rows {
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }

        let rowsCard = NSView()
        UITheme.styleCard(rowsCard)
        rowsCard.translatesAutoresizingMaskIntoConstraints = false
        rowsCard.addSubview(rowsStack)
        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: rowsCard.topAnchor, constant: 12),
            rowsStack.bottomAnchor.constraint(equalTo: rowsCard.bottomAnchor, constant: -12),
            rowsStack.leadingAnchor.constraint(equalTo: rowsCard.leadingAnchor, constant: 12),
            rowsStack.trailingAnchor.constraint(equalTo: rowsCard.trailingAnchor, constant: -12),
        ])

        conflictLabel = NSTextField(wrappingLabelWithString: "")
        conflictLabel.font = .systemFont(ofSize: 12)
        conflictLabel.textColor = UITheme.destructive
        conflictLabel.isHidden = true

        failureLabel = NSTextField(wrappingLabelWithString: "")
        failureLabel.font = .systemFont(ofSize: 12)
        failureLabel.textColor = UITheme.warning
        failureLabel.isHidden = true

        let content = NSStackView(views: [titleLabel, hintLabel, modifierBox, rowsCard,
                                          conflictLabel, failureLabel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        for view in content.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        // 13 行超出可视高度：整体内容放滚动区（玻璃垫在 pane 底层，滚动区透明）
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        UITheme.darkScroll(scroll)
        addSubview(scroll)
        scrollArea = scroll

        // NSClipView 自动管理 documentView 的边缘约束（滚动=改这些约束常量），
        // 手动给非零常量会与其冲突被打破——真机实证 28pt 边距被吃、内容贴死分割条。
        // 因此文档视图 0 常量钉 clip view，视觉边距由内层 padding 容器承担
        // （与通用/贴图 pane 的 28pt 布局模式一致）。
        let padding = NSView()
        padding.translatesAutoresizingMaskIntoConstraints = false
        padding.addSubview(content)
        scroll.documentView = padding

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 文档 0 常量钉 clip view：leading/top/宽 + 底边 ≥（拉大窗口撑满视口，
            // 旧滚动原点残留时被 layout() 夹持归零）
            padding.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            padding.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            padding.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            padding.bottomAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.bottomAnchor),

            // 内层 28pt 视觉边距（右侧同 28 对称）
            content.leadingAnchor.constraint(equalTo: padding.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: padding.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: padding.topAnchor, constant: 20),
            content.bottomAnchor.constraint(equalTo: padding.bottomAnchor, constant: -16),
        ])
    }

    /// 窗口/面板尺寸变化时夹持滚动原点：文档变矮（拉大窗口）后旧原点会超界，
    /// AppKit 不会自动回落——残留原点把内容推下去（真机顶部空白 230pt 的根因）。
    override func layout() {
        super.layout()
        guard let scroll = scrollArea, let doc = scroll.documentView else { return }
        let viewportHeight = scroll.contentView.bounds.height
        let maxOriginY = max(0, doc.bounds.height - viewportHeight)
        var origin = scroll.contentView.bounds.origin
        let clampedY = min(max(0, origin.y), maxOriginY)
        guard clampedY != origin.y else { return }
        origin.y = clampedY
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func makeFunctionRow(_ entry: (id: String, title: String, keyCode: UInt32)) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = UITheme.categoryColor(for: entry.id).cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
        ])

        let titleLabel = NSTextField(labelWithString: entry.title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = UITheme.textPrimary
        titleLabel.lineBreakMode = .byClipping

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let bindingButton = NSButton(title: "", target: self, action: #selector(bindingClicked(_:)))
        bindingButton.bezelStyle = .rounded
        bindingButton.identifier = NSUserInterfaceItemIdentifier(entry.id)
        bindingButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        bindingButtons[entry.id] = bindingButton

        let clearButton = NSButton(title: "×", target: self, action: #selector(clearClicked(_:)))
        clearButton.isBordered = false
        clearButton.toolTip = "清除该功能快捷键"
        clearButton.identifier = NSUserInterfaceItemIdentifier(entry.id + ".clear")
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let row = NSStackView(views: [dot, titleLabel, spacer, bindingButton, clearButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.identifier = NSUserInterfaceItemIdentifier(entry.id)
        return row
    }

    private func makeRow(label title: String, controls: [NSView]) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = UITheme.textPrimary
        let row = NSStackView(views: [label] + controls)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    /// 分组框（流光主题：fillColor 透明，玻璃从底层透出）；
    /// NSBox 需启用内容 Auto Layout 防塌缩（与 PinSettingsPaneView 同款约束）。
    private func makeGroupBox(title: String, content: NSView) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titleFont = .systemFont(ofSize: 13, weight: .medium)
        box.fillColor = .clear
        box.contentView = content
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: content.topAnchor, constant: -26),
            box.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: 12),
            box.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: -12),
            box.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: 12),
        ])
        return box
    }

    // MARK: - 状态刷新

    private func refreshAllLabels() {
        for entry in HotkeyPreferences.catalog {
            refreshLabel(for: entry.id)
        }
        refreshSummonLabel()
    }

    private func refreshLabel(for id: String) {
        guard let button = bindingButtons[id] else { return }
        button.title = prefs.displayLabel(for: id) ?? "无"
    }

    /// 面板呼出键显示名：功能键 F1~F12 用 functionKeyLabel，字母键用 letterLabel；nil = 无。
    private func refreshSummonLabel() {
        guard let summon = prefs.panelSummon else {
            summonButton.title = "无"
            return
        }
        summonButton.title = summon.functionKeyLabel
            ?? (Hotkey.letterLabel(for: summon.keyCode) ?? "?")
    }

    /// AppDelegate.applyHotkeyPreferences 的 selector：本文件同时编入测试 target，
    /// 而 AppDelegate.swift 仅在 app target，直接引用类型无法编译；经 NSApp.delegate
    /// 运行时派发（等价于 as? AppDelegate + 判空）。
    private static let applyHotkeySelector = NSSelectorFromString("applyHotkeyPreferences")

    /// 保存/清除/切主键后全量重放注册（经 AppDelegate），并按失败表刷新底部警告条。
    private func replayRegistrations() {
        guard let delegate = NSApp.delegate,
              delegate.responds(to: Self.applyHotkeySelector) else { return }
        let failures = delegate.perform(Self.applyHotkeySelector)?
            .takeUnretainedValue() as? [String: Hotkey] ?? [:]
        if let message = HotkeySettingsLogic.failureMessage(failures: failures) {
            failureLabel.stringValue = message
            failureLabel.isHidden = false
        } else {
            failureLabel.isHidden = true
        }
    }

    // MARK: - 录制交互

    @objc private func bindingClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        startRecording(for: id)
    }

    private func startRecording(for id: String) {
        removeRecordingMonitors()
        recordingTarget = .function(id)
        bindingButtons[id]?.title = "按下组合键…"
        conflictLabel.isHidden = true
        // 录制期间消费所有按键：Esc 不得关闭窗口、字母键不得落进搜索框等
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return nil
        }
        // 点击任意处结束录制（组合键在 keyDown 时已即时提交/否决，无挂起态）
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.endRecording()
            return nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard let target = recordingTarget else { return }
        let shiftHeld = event.modifierFlags.contains(.shift)
        switch HotkeyCapture.resolve(keyCode: UInt32(event.keyCode), shiftHeld: shiftHeld) {
        case .cancel:
            endRecording()
        case .ignore:
            break   // 纯修饰键按下：继续等待组合键
        case .bind(let binding):
            endRecording()
            switch target {
            case .function(let id):
                commit(binding: binding, for: id)
            case .panelSummon:
                // 呼出键无主修饰键语义：只取键码（⇧ 不入绑）
                commitSummon(keyCode: binding.keyCode)
            }
        }
    }

    private func endRecording() {
        removeRecordingMonitors()
        guard let target = recordingTarget else { return }
        recordingTarget = nil
        switch target {
        case .function(let id):
            refreshLabel(for: id)
        case .panelSummon:
            refreshSummonLabel()
        }
    }

    private func removeRecordingMonitors() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    // MARK: - 提交与动作

    /// 候选绑定即时冲突检测：有冲突红字提示且不保存不重放；无冲突保存 + 重放注册。
    private func commit(binding: HotkeyBinding, for id: String) {
        var candidate = prefs
        candidate.bindings[id] = binding
        if let message = HotkeySettingsLogic.conflictMessage(candidate: candidate, changingId: id) {
            conflictLabel.stringValue = message
            conflictLabel.isHidden = false
            return
        }
        conflictLabel.isHidden = true
        prefs = candidate
        prefs.save()
        replayRegistrations()
        refreshLabel(for: id)
    }

    // MARK: - 面板呼出键录制

    /// 点击「面板呼出键」按钮进入录制：Esc 取消、纯修饰键忽略、其他键入绑（无主修饰键语义）。
    @objc private func summonClicked() {
        startSummonRecording()
    }

    private func startSummonRecording() {
        removeRecordingMonitors()
        recordingTarget = .panelSummon
        summonButton.title = "按下按键…"
        conflictLabel.isHidden = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return nil
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.endRecording()
            return nil
        }
    }

    /// 呼出键提交：保存 Hotkey(keyCode:) + 重放注册（AppDelegate 原样注册，不叠主修饰键）。
    private func commitSummon(keyCode: UInt32) {
        prefs.panelSummon = Hotkey(keyCode: keyCode)
        prefs.save()
        replayRegistrations()
        refreshSummonLabel()
    }

    @objc private func clearSummonClicked() {
        endRecording()
        guard prefs.panelSummon != nil else { return }
        prefs.panelSummon = nil
        prefs.save()
        conflictLabel.isHidden = true
        replayRegistrations()
        refreshSummonLabel()
    }

    @objc private func modifierChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard index >= 0, index < PrimaryModifier.allCases.count else { return }
        endRecording()
        prefs.primaryModifier = PrimaryModifier.allCases[index]
        prefs.save()
        conflictLabel.isHidden = true
        replayRegistrations()
        refreshAllLabels()
    }

    @objc private func clearClicked(_ sender: NSButton) {
        // 标识符带 ".clear" 后缀，与组合键按钮区分
        guard let raw = sender.identifier?.rawValue, raw.hasSuffix(".clear") else { return }
        let id = String(raw.dropLast(".clear".count))
        endRecording()
        guard prefs.bindings[id] != nil else { return }
        prefs.bindings[id] = nil
        prefs.save()
        conflictLabel.isHidden = true
        replayRegistrations()
        refreshLabel(for: id)
    }
}
