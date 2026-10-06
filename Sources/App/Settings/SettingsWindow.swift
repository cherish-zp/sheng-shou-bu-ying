import AVFoundation
import AppKit

/// 设置窗口：左侧分类栏 + 右侧详情面板（仿系统设置布局）。
/// 现包含「通用」「快速片段」「贴图」三个分类。
final class SettingsWindow: NSWindow, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {

    private var tableView: NSTableView!
    private var pinPane: PinSettingsPaneView!
    private var generalPane: GeneralSettingsPaneView!
    private var snippetPane: SnippetManagerView!
    private var recordingPane: RecordingSettingsPaneView!
    private let moduleRegistry: AppModuleRegistry
    private let onModuleStateChanged: (String, Bool) -> Void

    private let sidebarItems = ["通用", "快速片段", "贴图", "录屏"]
    private static let cellID = NSUserInterfaceItemIdentifier("settingsSidebarCell")

    init(moduleRegistry: AppModuleRegistry, onModuleStateChanged: @escaping (String, Bool) -> Void) {
        self.moduleRegistry = moduleRegistry
        self.onModuleStateChanged = onModuleStateChanged
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "设置"
        titlebarAppearsTransparent = true
        center()
        isReleasedWhenClosed = false
        minSize = NSSize(width: 680, height: 460)
        delegate = self
        buildUI()
    }

    func showAndFocus(category: Int = 0) {
        selectCategory(category)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI 构建

    private func buildUI() {
        let bg = NSVisualEffectView()
        bg.material = .windowBackground
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.autoresizingMask = [.width, .height]
        contentView = bg

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(split)

        // 左侧分类栏
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        // 点击列表空白处不取消选中：取消选择会让右侧详情面板被误隐藏
        tableView.allowsEmptySelection = false
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("settingsSidebar"))
        tableView.addTableColumn(column)
        scroll.documentView = tableView
        sidebar.addSubview(scroll)

        // 右侧详情：分类设置面板
        generalPane = GeneralSettingsPaneView(moduleRegistry: moduleRegistry)
        generalPane.onModuleStateChanged = onModuleStateChanged
        snippetPane = SnippetManagerView()
        pinPane = PinSettingsPaneView()
        recordingPane = RecordingSettingsPaneView()

        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(generalPane)
        split.addArrangedSubview(snippetPane)
        split.addArrangedSubview(pinPane)
        split.addArrangedSubview(recordingPane)
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        sidebar.widthAnchor.constraint(equalToConstant: 180).isActive = true

        // arrangedSubview 的位置由 NSSplitView 内部约束管理；
        // 手动钉边会与其冲突（面板被拉回 x=0 盖住侧栏，整窗错乱）。
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            split.topAnchor.constraint(equalTo: bg.topAnchor),
            split.bottomAnchor.constraint(equalTo: bg.bottomAnchor),

            scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: sidebar.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
        ])

        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        selectCategory(0)
    }

    private func selectCategory(_ index: Int) {
        guard tableView.selectedRow == index else {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            return
        }
        applySelectedCategory(index)
    }

    private func applySelectedCategory(_ index: Int) {
        generalPane?.isHidden = index != 0
        snippetPane?.isHidden = index != 1
        pinPane?.isHidden = index != 2
        recordingPane?.isHidden = index != 3
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { sidebarItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? NSTableCellView
            ?? NSTableCellView()
        cell.identifier = Self.cellID
        let label = NSTextField(labelWithString: sidebarItems[row])
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        // 防御：空选择（row = -1，如点击列表空白/编程取消）恢复选中首项，避免右侧面板被误隐藏
        guard row >= 0 else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            return
        }
        // buildUI 早期（右侧面板尚未创建）也可能触发选中事件，容忍之
        applySelectedCategory(row)
    }
}

/// 贴图设置面板：呼吸灯样式与外观（高度/距顶部距离/颜色），
/// 更改立即保存并通知已打开贴图。
final class PinSettingsPaneView: NSView {

    private let topBarRadio: NSButton
    private let cornerDotRadio: NSButton
    private var heightSlider: NSSlider!
    private var topInsetSlider: NSSlider!
    private var heightValueLabel: NSTextField!
    private var topInsetValueLabel: NSTextField!
    private var swatchButtons: [NSButton] = []
    private var selectedColorHex: String = PinIndicatorColor.defaultHex

    init() {
        topBarRadio = NSButton(radioButtonWithTitle: "顶部横条呼吸灯", target: nil, action: nil)
        cornerDotRadio = NSButton(radioButtonWithTitle: "左上角圆点", target: nil, action: nil)
        super.init(frame: .zero)
        buildUI()
        syncFromStore()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    // MARK: - UI 构建

    private func buildUI() {
        let titleLabel = NSTextField(labelWithString: "贴图")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let hintLabel = NSTextField(labelWithString: "呼吸灯提示当前存在贴图；更改立即对已打开的贴图生效。")
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor

        topBarRadio.target = self
        topBarRadio.action = #selector(styleChanged(_:))
        cornerDotRadio.target = self
        cornerDotRadio.action = #selector(styleChanged(_:))

        let radioStack = NSStackView(views: [topBarRadio, cornerDotRadio])
        radioStack.orientation = .vertical
        radioStack.alignment = .leading
        radioStack.spacing = 10
        // 作为 NSBox.contentView 必须用 Auto Layout，否则 box 无法据内容计算高度，
        // 会塌缩成仅剩标题条（16pt），单选按钮溢出并与面板其他元素叠压
        radioStack.translatesAutoresizingMaskIntoConstraints = false

        let styleBox = makeGroupBox(title: "呼吸灯样式", content: radioStack)

        // 呼吸灯外观（仅顶部横条样式生效）
        heightSlider = NSSlider(value: Double(PinIndicatorAppearance.defaultHeight),
                                minValue: Double(PinIndicatorAppearance.heightRange.lowerBound),
                                maxValue: Double(PinIndicatorAppearance.heightRange.upperBound),
                                target: self, action: #selector(appearanceChanged(_:)))
        topInsetSlider = NSSlider(value: Double(PinIndicatorAppearance.defaultTopInset),
                                  minValue: Double(PinIndicatorAppearance.topInsetRange.lowerBound),
                                  maxValue: Double(PinIndicatorAppearance.topInsetRange.upperBound),
                                  target: self, action: #selector(appearanceChanged(_:)))
        heightValueLabel = NSTextField(labelWithString: "\(PinIndicatorAppearance.defaultHeight)pt")
        topInsetValueLabel = NSTextField(labelWithString: "\(PinIndicatorAppearance.defaultTopInset)pt")
        let valueLabels: [NSTextField] = [heightValueLabel, topInsetValueLabel]
        for label in valueLabels {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
        }

        heightSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        topInsetSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true

        let heightRow = makeRow(label: "呼吸灯高度", controls: [heightSlider, heightValueLabel])
        let insetRow = makeRow(label: "距顶部距离", controls: [topInsetSlider, topInsetValueLabel])

        var swatches: [NSView] = []
        for hex in PinIndicatorColor.paletteHexes {
            swatches.append(makeSwatch(hex: hex))
        }
        let swatchStack = NSStackView(views: swatches)
        swatchStack.orientation = .horizontal
        swatchStack.spacing = 8
        let colorRow = makeRow(label: "颜色", controls: [swatchStack])

        let appearanceStack = NSStackView(views: [heightRow, insetRow, colorRow])
        appearanceStack.orientation = .vertical
        appearanceStack.alignment = .leading
        appearanceStack.spacing = 10
        appearanceStack.translatesAutoresizingMaskIntoConstraints = false

        let appearanceBox = makeGroupBox(title: "呼吸灯外观", content: appearanceStack)

        let stack = NSStackView(views: [titleLabel, hintLabel, styleBox, appearanceBox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
        ])
    }

    /// 分组框：NSBox 不会据替换后的 contentView 自动撑高（会塌缩成仅剩 16pt 标题条，
    /// 内容溢出叠压），必须启用内容 Auto Layout 并显式把边框绑定到内容。
    /// 顶部常数 = 标题区高度，其余 = 内容边距。
    private func makeGroupBox(title: String, content: NSView) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titleFont = .systemFont(ofSize: 13, weight: .medium)
        box.contentView = content
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: content.topAnchor, constant: -26),
            box.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: 12),
            box.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: -12),
            box.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: 12),
        ])
        return box
    }

    /// 设置行：左对齐固定宽度标签 + 控件。
    private func makeRow(label title: String, controls: [NSView]) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let row = NSStackView(views: [label] + controls)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    /// 颜色色块：18pt 圆形按钮，选中时描边。
    private func makeSwatch(hex: String) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(swatchClicked(_:)))
        button.isBordered = false
        button.identifier = NSUserInterfaceItemIdentifier(hex)
        button.wantsLayer = true
        button.layer?.backgroundColor = PinIndicatorColor.color(fromHex: hex)?.cgColor
        button.layer?.cornerRadius = 9
        button.layer?.borderWidth = 0
        button.widthAnchor.constraint(equalToConstant: 18).isActive = true
        button.heightAnchor.constraint(equalToConstant: 18).isActive = true
        swatchButtons.append(button)
        return button
    }

    // MARK: - 状态同步

    private func syncFromStore() {
        let state = PinSettingsStore.defaultStore().load()
        topBarRadio.state = state.indicatorStyle == .topBar ? .on : .off
        cornerDotRadio.state = state.indicatorStyle == .cornerDot ? .on : .off
        heightSlider.integerValue = Int(state.indicatorHeight)
        topInsetSlider.integerValue = Int(state.indicatorTopInset)
        heightValueLabel.stringValue = "\(Int(state.indicatorHeight))pt"
        topInsetValueLabel.stringValue = "\(Int(state.indicatorTopInset))pt"
        selectedColorHex = state.indicatorColorHex
        updateSwatchSelection()
    }

    private func updateSwatchSelection() {
        for button in swatchButtons {
            let selected = button.identifier?.rawValue == selectedColorHex
            button.layer?.borderWidth = selected ? 2 : 0
            button.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
    }

    // MARK: - 动作

    @objc private func styleChanged(_ sender: NSButton) {
        let style: PinIndicatorStyle = sender == topBarRadio ? .topBar : .cornerDot
        var state = PinSettingsStore.defaultStore().load()
        state.indicatorStyle = style
        PinSettingsStore.defaultStore().save(state)
        NotificationCenter.default.post(name: .pinIndicatorStyleDidChange, object: nil)
    }

    @objc private func swatchClicked(_ sender: NSButton) {
        guard let hex = sender.identifier?.rawValue else { return }
        selectedColorHex = hex
        updateSwatchSelection()
        persistAppearance()
    }

    @objc private func appearanceChanged(_ sender: NSSlider) {
        heightValueLabel.stringValue = "\(heightSlider.integerValue)pt"
        topInsetValueLabel.stringValue = "\(topInsetSlider.integerValue)pt"
        persistAppearance()
    }

    private func persistAppearance() {
        var state = PinSettingsStore.defaultStore().load()
        state.indicatorHeight = CGFloat(heightSlider.integerValue)
        state.indicatorTopInset = CGFloat(topInsetSlider.integerValue)
        state.indicatorColorHex = selectedColorHex
        PinSettingsStore.defaultStore().save(state)
        NotificationCenter.default.post(name: .pinIndicatorStyleDidChange, object: nil)
    }
}

/// 录屏设置面板：系统声音开关（默认开）、麦克风开关（默认关，开启时请求麦克风权限）、
/// 帧率 30/60。更改立即写入 RecordingConfigStore 持久化，下次开录即生效。
final class RecordingSettingsPaneView: NSView {

    private let systemAudioSwitch = NSSwitch()
    private let micSwitch = NSSwitch()
    private let frameRateControl = NSSegmentedControl(labels: ["30 fps", "60 fps"],
                                                      trackingMode: .selectOne, target: nil, action: nil)
    private let store = RecordingConfigStore()

    init() {
        super.init(frame: .zero)
        buildUI()
        syncFromStore()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    // MARK: - UI 构建

    private func buildUI() {
        let titleLabel = NSTextField(labelWithString: "录屏")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let hintLabel = NSTextField(labelWithString: "F4 呼出录屏；更改立即生效于下一次录制。")
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor

        for sw in [systemAudioSwitch, micSwitch] {
            sw.target = self
            sw.controlSize = .regular
        }
        systemAudioSwitch.action = #selector(systemAudioChanged(_:))
        micSwitch.action = #selector(micChanged(_:))

        let systemAudioRow = makeRow(label: "系统声音", controls: [systemAudioSwitch])
        let micRow = makeRow(label: "麦克风", controls: [micSwitch])
        let audioStack = NSStackView(views: [systemAudioRow, micRow])
        audioStack.orientation = .vertical
        audioStack.alignment = .leading
        audioStack.spacing = 10
        audioStack.translatesAutoresizingMaskIntoConstraints = false
        let audioBox = makeGroupBox(title: "音频", content: audioStack)

        frameRateControl.target = self
        frameRateControl.action = #selector(frameRateChanged(_:))
        frameRateControl.selectedSegment = 0
        let frameRateRow = makeRow(label: "帧率", controls: [frameRateControl])
        let videoStack = NSStackView(views: [frameRateRow])
        videoStack.orientation = .vertical
        videoStack.alignment = .leading
        videoStack.spacing = 10
        videoStack.translatesAutoresizingMaskIntoConstraints = false
        let videoBox = makeGroupBox(title: "视频", content: videoStack)

        let savePathLabel = NSTextField(labelWithString: RecordingConfig.defaultSaveDirectory.path)
        savePathLabel.font = .systemFont(ofSize: 11)
        savePathLabel.textColor = .secondaryLabelColor
        savePathLabel.lineBreakMode = .byTruncatingMiddle
        let saveRow = makeRow(label: "保存到", controls: [savePathLabel])
        let saveStack = NSStackView(views: [saveRow])
        saveStack.orientation = .vertical
        saveStack.alignment = .leading
        saveStack.spacing = 10
        saveStack.translatesAutoresizingMaskIntoConstraints = false
        let saveBox = makeGroupBox(title: "输出", content: saveStack)

        let stack = NSStackView(views: [titleLabel, hintLabel, audioBox, videoBox, saveBox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
        ])
    }

    /// 分组框：与 PinSettingsPaneView 同款（NSBox 需启用内容 Auto Layout 防塌缩）。
    private func makeGroupBox(title: String, content: NSView) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titleFont = .systemFont(ofSize: 13, weight: .medium)
        box.contentView = content
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: content.topAnchor, constant: -26),
            box.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: 12),
            box.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: -12),
            box.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: 12),
        ])
        return box
    }

    /// 设置行：固定宽度标签 + 控件。
    private func makeRow(label title: String, controls: [NSView]) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let row = NSStackView(views: [label] + controls)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    // MARK: - 状态同步与持久化

    private func syncFromStore() {
        let config = store.load()
        systemAudioSwitch.state = config.systemAudioEnabled ? .on : .off
        micSwitch.state = config.microphoneEnabled ? .on : .off
        frameRateControl.selectedSegment = config.frameRate == .fps60 ? 1 : 0
    }

    private func persist(mutate: (inout RecordingConfig) -> Void) {
        var config = store.load()
        mutate(&config)
        store.save(config)
    }

    // MARK: - 动作

    @objc private func systemAudioChanged(_ sender: NSSwitch) {
        persist { $0.systemAudioEnabled = sender.state == .on }
    }

    /// 麦克风开启时请求权限：拒绝则回拨开关；已拒绝过则提示去系统设置。
    @objc private func micChanged(_ sender: NSSwitch) {
        guard sender.state == .on else {
            persist { $0.microphoneEnabled = false }
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            persist { $0.microphoneEnabled = true }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.micSwitch.state = granted ? .on : .off
                    self.persist { $0.microphoneEnabled = granted }
                }
            }
        default:
            sender.state = .off
            persist { $0.microphoneEnabled = false }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "无法启用麦克风"
            alert.informativeText = "麦克风权限已被拒绝，请在「系统设置 → 隐私与安全性 → 麦克风」中允许 mac_tool_pro。"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    @objc private func frameRateChanged(_ sender: NSSegmentedControl) {
        let rate: RecordingFrameRate = sender.selectedSegment == 1 ? .fps60 : .fps30
        persist { $0.frameRate = rate }
    }
}
