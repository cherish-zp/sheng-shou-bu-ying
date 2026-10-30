import AppKit

/// 文本工具集窗口：输入区 + 工具按钮排 + 输出区（深色面板，UITheme）。
/// 工具全部来自 TextToolkit 纯逻辑。
final class TextToolkitWindowController: NSObject {

    let window: NSWindow
    private let inputView: NSTextView
    private let outputView: NSTextView
    private var outputStorage: NSAttributedString = .init()

    private enum Tool: String, CaseIterable {
        case jsonValidate = "JSON 校验"
        case jsonPretty = "JSON 美化"
        case md5 = "MD5"
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case base64Encode = "Base64 编码"
        case base64Decode = "Base64 解码"
        case urlEncode = "URL 编码"
        case urlDecode = "URL 解码"
        case removeBlankLines = "去空行"
        case removeDuplicateLines = "去重行"
        case sortLines = "排序"
    }

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)

        // 输入区
        let inputScroll = NSScrollView()
        inputScroll.hasVerticalScroller = true
        inputScroll.drawsBackground = false
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        UITheme.styleCard(inputScroll)
        let input = NSTextView(frame: NSRect(x: 0, y: 0, width: 690, height: 160))
        input.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        input.textColor = UITheme.textPrimary
        input.drawsBackground = false
        input.isRichText = false
        input.autoresizingMask = [.width]
        inputScroll.documentView = input
        inputView = input

        // 输出区
        let outputScroll = NSScrollView()
        outputScroll.hasVerticalScroller = true
        outputScroll.drawsBackground = false
        outputScroll.translatesAutoresizingMaskIntoConstraints = false
        UITheme.styleCard(outputScroll)
        let output = NSTextView(frame: NSRect(x: 0, y: 0, width: 690, height: 160))
        output.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        output.textColor = UITheme.textPrimary
        output.drawsBackground = false
        output.isEditable = false
        output.autoresizingMask = [.width]
        outputScroll.documentView = output
        outputView = output

        super.init()

        window.title = "文本工具集"
        window.isReleasedWhenClosed = false
        UITheme.applyDark(window)
        window.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        UITheme.stylePanel(content)

        // 工具按钮排
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        for tool in Tool.allCases {
            let button = NSButton(title: tool.rawValue, target: self, action: #selector(runTool(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.tag = Tool.allCases.firstIndex(of: tool) ?? 0
            stack.addArrangedSubview(button)
        }
        content.addSubview(stack)

        
let copyButton = NSButton(title: "复制结果", target: self, action: #selector(copyOutput))
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .small
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(copyButton)

        let hint = NSTextField(labelWithString: "粘贴文本 → 点工具 → 复制结果")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = UITheme.textSecondary
        hint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hint)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),

            inputScroll.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),
            inputScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            inputScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            inputScroll.heightAnchor.constraint(equalTo: content.heightAnchor, multiplier: 0.36),

            outputScroll.topAnchor.constraint(equalTo: inputScroll.bottomAnchor, constant: 10),
            outputScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            outputScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            outputScroll.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -8),

            copyButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            copyButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            hint.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
        ])
    }

    func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        inputView.window?.makeFirstResponder(inputView)
    }

    @objc private func runTool(_ sender: NSButton) {
        let tool = Tool.allCases[sender.tag]
        let input = inputView.string
        let result: String
        switch tool {
        case .jsonValidate:
            let check = TextToolkit.validateJSON(input)
            result = check.isValid ? "✓ 合法 JSON" : "✗ \(check.errorMessage ?? "非法")"
        case .jsonPretty:
            result = TextToolkit.prettyJSON(input) ?? "✗ 非法 JSON"
        case .md5: result = TextToolkit.md5(input)
        case .sha1: result = TextToolkit.sha1(input)
        case .sha256: result = TextToolkit.sha256(input)
        case .base64Encode: result = TextToolkit.base64Encode(input)
        case .base64Decode:
            result = TextToolkit.base64Decode(input) ?? "✗ 解码失败"
        case .urlEncode: result = TextToolkit.urlEncode(input)
        case .urlDecode:
            result = TextToolkit.urlDecode(input) ?? "✗ 解码失败"
        case .removeBlankLines: result = TextToolkit.removeBlankLines(input)
        case .removeDuplicateLines: result = TextToolkit.removeDuplicateLines(input)
        case .sortLines: result = TextToolkit.sortLines(input)
        }
        outputStorage = NSAttributedString(string: result + "\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UITheme.textPrimary,
        ])
        outputView.textStorage?.setAttributedString(outputStorage)
    }

    @objc private func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputView.string, forType: .string)
    }
}
