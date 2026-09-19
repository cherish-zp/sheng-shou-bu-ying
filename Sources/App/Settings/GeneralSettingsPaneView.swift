import AppKit

/// 通用设置面板：Finder 工具、App 模块开关与诊断入口。
final class GeneralSettingsPaneView: NSView {

    private let moduleRegistry: AppModuleRegistry
    var onModuleStateChanged: ((String, Bool) -> Void)?

    init(moduleRegistry: AppModuleRegistry) {
        self.moduleRegistry = moduleRegistry
        super.init(frame: .zero)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    private func buildUI() {
        let titleLabel = NSTextField(labelWithString: "通用")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let hintLabel = NSTextField(labelWithString: "控制 Finder 右键工具与全局功能模块；关闭后热键和菜单入口同步停用。")
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 2

        var moduleRows: [NSView] = []
        for module in moduleRegistry.modules {
            moduleRows.append(makeModuleRow(module: module))
        }
        let moduleStack = NSStackView(views: moduleRows)
        moduleStack.orientation = .vertical
        moduleStack.alignment = .leading
        moduleStack.spacing = 10

        var toolRows: [NSView] = ToolRegistry.shared.tools.map(makeToolRow)
        if toolRows.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "暂无可用工具")
            emptyLabel.textColor = .tertiaryLabelColor
            toolRows = [emptyLabel]
        }
        let toolStack = NSStackView(views: toolRows)
        toolStack.orientation = .vertical
        toolStack.alignment = .leading
        toolStack.spacing = 10

        let moduleBox = makeGroupBox(title: "功能模块", content: moduleStack)
        let toolBox = makeGroupBox(title: "Finder 工具", content: toolStack)

        let logButton = NSButton(title: "查看热键日志", target: self, action: #selector(showHotkeyLog))
        logButton.bezelStyle = .rounded

        let diagnosticStack = NSStackView(views: [logButton])
        diagnosticStack.orientation = .vertical
        diagnosticStack.alignment = .leading
        diagnosticStack.spacing = 8
        let diagnosticBox = makeGroupBox(title: "诊断", content: diagnosticStack)

        let stack = NSStackView(views: [titleLabel, hintLabel, moduleBox, toolBox, diagnosticBox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
        ])
    }

    private func makeModuleRow(module: AppModule) -> NSView {
        let suffix = module.defaultHotkey.functionKeyLabel.map { " (\($0))" } ?? ""
        let button = NSButton(
            checkboxWithTitle: module.title + suffix,
            target: self,
            action: #selector(moduleStateChanged(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier(module.id)
        button.state = moduleRegistry.isEnabled(module.id) ? .on : .off
        return button
    }

    private func makeToolRow(tool: Tool) -> NSView {
        let button = NSButton(
            checkboxWithTitle: tool.title,
            target: self,
            action: #selector(toolStateChanged(_:))
        )
        button.identifier = NSUserInterfaceItemIdentifier(tool.id)
        button.state = ToolConfig.isEnabled(tool.id) ? .on : .off
        return button
    }

    private func makeGroupBox(title: String, content: NSView) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titleFont = .systemFont(ofSize: 13, weight: .medium)
        box.contentView = content
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: content.topAnchor, constant: -26),
            box.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: 12),
            box.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: -12),
            box.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: 12),
        ])
        return box
    }

    @objc private func moduleStateChanged(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        let enabled = sender.state == .on
        moduleRegistry.setEnabled(id, enabled)
        onModuleStateChanged?(id, enabled)
    }

    @objc private func toolStateChanged(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        ToolConfig.setEnabled(id, sender.state == .on)
    }

    @objc private func showHotkeyLog() {
        NSWorkspace.shared.open(DiagLog.logURL)
    }
}
