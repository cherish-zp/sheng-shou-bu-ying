import AppKit

#if canImport(Translation)
import Translation
#endif

/// 翻译面板：系统 Translation 框架（macOS 15+ 离线）；旧系统提示升级。
final class TranslatePanelController: NSObject {
    let window: NSWindow
    private let sourceView: NSTextView
    private let outputView: NSTextView
    private let statusLabel: NSTextField
    private var session: Any?  // TranslationSession（macOS 15+ 持有）

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        let source = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 150))
        let output = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 150))
        sourceView = source
        outputView = output
        statusLabel = NSTextField(labelWithString: "")

        window.title = "翻译"
        window.isReleasedWhenClosed = false
        window.center()
        super.init()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 400))
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        UITheme.stylePanel(content)

        for (view, y) in [(sourceScroll(), 10.0), (outputScroll(), 210.0)] {}
        let inScroll = wrap(source); let outScroll = wrap(output)
        content.addSubview(inScroll); content.addSubview(outScroll)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        let button = NSButton(title: "翻译", target: self, action: #selector(translateNow))
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(button)

        NSLayoutConstraint.activate([
            inScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            inScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            inScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            inScroll.heightAnchor.constraint(equalToConstant: 170),
            outScroll.topAnchor.constraint(equalTo: inScroll.bottomAnchor, constant: 10),
            outScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            outScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            outScroll.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -10),
            button.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            button.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            statusLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
        ])
        for v in [source, output] {
            v.font = .systemFont(ofSize: 13)
            v.textColor = UITheme.textPrimary
            v.drawsBackground = false
            v.autoresizingMask = [.width]
        }
        output.isEditable = false
        if #unavailable(macOS 15) {
            statusLabel.stringValue = "面板翻译需要 macOS 26 及以上版本"
        }
    }

    private func wrap(_ view: NSTextView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        UITheme.styleCard(scroll)
        scroll.documentView = view
        return scroll
    }

    private func sourceScroll() -> NSScrollView { wrap(sourceView) }
    private func outputScroll() -> NSScrollView { wrap(outputView) }

    func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func translateNow() {
        let text = sourceView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
#if canImport(Translation)
        if #available(macOS 26, *) {
            statusLabel.stringValue = "翻译中…"
            Task {
                do {
                    let session = try await TranslationSession(
                        installedSource: Locale.Language(identifier: "zh-Hans"),
                        target: Locale.Language(identifier: "en"))
                    let translated = try await session.translate(text)
                    outputView.string = translated.targetText
                    statusLabel.stringValue = "完成"
                } catch {
                    statusLabel.stringValue = "翻译失败：\(error.localizedDescription)"
                }
            }
            return
        }
#endif
        statusLabel.stringValue = "面板翻译需要 macOS 26 及以上版本"
    }
}
