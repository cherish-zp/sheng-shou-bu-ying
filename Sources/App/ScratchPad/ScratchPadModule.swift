import AppKit

/// 草稿速记：置顶小窗随手记文本（自动保存，锁定置顶参考对标浮引草稿）。
final class ScratchPadModule: NSObject, NSTextViewDelegate {
    let id = "scratchpad"
    let title = "速记"

    private var window: NSWindow?
    private var textView: NSTextView?
    private let storageURL: URL
    private var saveWorkItem: DispatchWorkItem?

    init(storageURL: URL? = nil) {
        let dir = AppSupportDirectory.url
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = storageURL ?? dir.appendingPathComponent("scratchpad.txt")
        super.init()
    }

    func perform() {
        if window == nil { buildWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        loadIfNeeded()
    }

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "速记（自动保存 · 置顶）"
        window.isReleasedWhenClosed = false
        UITheme.applyDark(window)
        window.level = .floating   // 置顶参考
        window.center()
        self.window = window

        let content = NSView(frame: window.contentView!.frame)
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        UITheme.stylePanel(content)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        UITheme.styleCard(scroll)
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
        text.font = .systemFont(ofSize: 13)
        text.textColor = UITheme.textPrimary
        text.drawsBackground = false
        text.isRichText = false
        text.autoresizingMask = [.width]
        scroll.documentView = text
        content.addSubview(scroll)
        textView = text
        text.delegate = self

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
    }

    private var loaded = false
    private func loadIfNeeded() {
        guard !loaded, let text = textView else { return }
        text.string = (try? String(contentsOf: storageURL, encoding: .utf8)) ?? ""
        loaded = true
    }

    func textDidChange(_ notification: Notification) {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let text = self?.textView?.string else { return }
            try? text.write(to: self?.storageURL ?? URL(fileURLWithPath: "/dev/null"),
                            atomically: true, encoding: .utf8)
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }
}
