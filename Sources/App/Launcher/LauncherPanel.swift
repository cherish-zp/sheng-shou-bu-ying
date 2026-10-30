import AppKit

/// 启动器面板：深色网格，绑定常用 App（JSON 持久化），点击打开。
final class LauncherPanelController: NSObject {
    let window: NSWindow
    private var apps: [URL] { didSet { persist(); rebuildGrid() } }
    private var grid: NSStackView?

    private var configURL: URL {
        AppSupportDirectory.url.appendingPathComponent("launcher_apps.json")
    }

    override init() {
        let saved: [URL] = {
            guard let data = try? Data(contentsOf: AppSupportDirectory.url.appendingPathComponent("launcher_apps.json")) else { return [] }
            return (try? JSONDecoder().decode([URL].self, from: data)) ?? []
        }()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        apps = saved
        super.init()
        window.title = "启动器"
        window.isReleasedWhenClosed = false
        UITheme.applyDark(window)
        window.center()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 300))
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        UITheme.stylePanel(content)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 6
        grid.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = grid
        self.grid = grid
        content.addSubview(scroll)

        let add = NSButton(title: "添加应用…", target: self, action: #selector(addApp))
        add.bezelStyle = .rounded
        add.controlSize = .small
        add.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(add)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: add.topAnchor, constant: -8),
            add.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            add.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
        rebuildGrid()
    }

    func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        rebuildGrid()
    }

    private func rebuildGrid() {
        grid?.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if apps.isEmpty {
            grid?.addArrangedSubview(NSTextField(labelWithString: "点「添加应用…」绑定常用 App"))
        }
        for url in apps {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 22).isActive = true
            let click = LauncherAppButton(title: url.deletingPathExtension().lastPathComponent,
                                          target: self, action: #selector(launchApp(_:)))
            click.isBordered = false
            click.contentTintColor = UITheme.textPrimary
            click.appURL = url
            row.addArrangedSubview(icon)
            row.addArrangedSubview(click)
            grid?.addArrangedSubview(row)
        }
    }

    @objc private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !apps.contains(url) { apps.append(url) }
    }

    @objc private func launchApp(_ sender: LauncherAppButton) {
        guard let url = sender.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(apps) {
            try? data.write(to: configURL, options: .atomic)
        }
    }
}

/// 携带目标 App URL 的按钮。
final class LauncherAppButton: NSButton {
    var appURL: URL?
}
