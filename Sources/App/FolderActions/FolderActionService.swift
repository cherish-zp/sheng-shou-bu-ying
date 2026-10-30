import AppKit

/// App 侧文件夹动作执行器：粘贴/复制至/移动到/彻底删除/显示隐藏/扩展名开关。
/// 全部在主线程执行（请求轮询本身在主线程），涉及 UI 的走 NSAlert/NSOpenPanel。
final class FolderActionService {

    /// 测试注入点：剪贴板文件 URL。
    var clipboardFileURLs: () -> [URL] = {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL])?.filter { $0.isFileURL } ?? []
    }
    /// 测试注入点：选择目标文件夹。
    var chooseDirectory: () -> URL? = {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "选择目标文件夹"
        return panel.runModal() == .OK ? panel.url : nil
    }
    /// 测试注入点：确认弹窗（返回是否继续）。
    var confirm: (String, String) -> Bool = { title, text in
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
    /// 测试注入点：执行 shell（显示隐藏/扩展名切换用）。
    var runShell: ([String]) -> Void = { args in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = args
        try? process.run()
        process.waitUntilExit()
    }
    /// 测试注入点：重启 Finder。
    var restartFinder: () -> Void = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
    }

    func handle(_ request: FolderActionRequest) {
        let directory = URL(fileURLWithPath: request.directory)
        let paths = request.paths.map { URL(fileURLWithPath: $0) }
        switch request.action {
        case .paste: paste(into: directory)
        case .copyTo: copy(paths)
        case .moveTo: move(paths)
        case .deleteForever: deleteForever(paths)
        case .showHidden: toggleShowHidden(in: directory)
        case .toggleExtension: toggleExtension()
        }
    }

    private func paste(into directory: URL) {
        let fm = FileManager.default
        let existing = Set((try? fm.contentsOfDirectory(atPath: directory.path)) ?? [])
        for source in clipboardFileURLs() {
            let unique = FileNameResolver.unique(baseName: source.lastPathComponent, existingNames: existing)
            try? fm.copyItem(at: source, to: directory.appendingPathComponent(unique))
        }
    }

    private func copy(_ paths: [URL]) {
        guard !paths.isEmpty, let destination = chooseDirectory() else { return }
        let fm = FileManager.default
        for source in paths {
            let target = destination.appendingPathComponent(source.lastPathComponent)
            if !fm.fileExists(atPath: target.path) {
                try? fm.copyItem(at: source, to: target)
            }
        }
    }

    private func move(_ paths: [URL]) {
        guard !paths.isEmpty, let destination = chooseDirectory() else { return }
        let fm = FileManager.default
        for source in paths {
            let target = destination.appendingPathComponent(source.lastPathComponent)
            if !fm.fileExists(atPath: target.path) {
                try? fm.moveItem(at: source, to: target)
            }
        }
    }

    private func deleteForever(_ paths: [URL]) {
        guard !paths.isEmpty else { return }
        let listing = paths.prefix(6).map(\.lastPathComponent).joined(separator: "\n")
        let more = paths.count > 6 ? "\n…等 \(paths.count) 项" : ""
        guard confirm("彻底删除？", "\(paths.count) 项将被永久删除（不可恢复）：\n\(listing)\(more)") else { return }
        let fm = FileManager.default
        for path in paths {
            try? fm.removeItem(at: path)
        }
    }

    private func toggleShowHidden(in directory: URL) {
        let defaultsPath = directory.path + "/.hidden-marker" // 占位：实际切换全局 Finder 设置
        _ = defaultsPath
        let current = UserDefaults.standard.bool(forKey: "lastShowHiddenState")
        let next = !current
        UserDefaults.standard.set(next, forKey: "lastShowHiddenState")
        runShell(["write", "com.apple.finder", "AppleShowAllFiles", "-bool", next ? "true" : "false"])
        restartFinder()
    }

    private func toggleExtension() {
        let current = UserDefaults.standard.bool(forKey: "lastShowExtensionState")
        let next = !current
        UserDefaults.standard.set(next, forKey: "lastShowExtensionState")
        runShell(["write", "NSGlobalDomain", "AppleShowAllExtensions", "-bool", next ? "true" : "false"])
        restartFinder()
    }
}
