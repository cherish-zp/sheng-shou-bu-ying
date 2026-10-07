import FinderSync
import AppKit
import os.log

private let logger = Logger(subsystem: "com.zp.shengshoubuying", category: "FinderSyncExt")

@objc(FinderSyncExt)
final class FinderSyncExt: FIFinderSync {
    /// 当次菜单的调用表。每次 menu(for:) 清空重建，用菜单项 tag 作为下标找回 {工具id, urls}。
    /// 不用 representedObject：Finder Sync 菜单项跨进程到 Finder 时 representedObject 会丢失。
    private let invocations = ToolInvocationTable()

    override init() {
        super.init()
        // 支持目录迁移（mac_tool_pro → 圣手捕影），工具开关等持久数据随之搬入新目录
        AppSupportDirectory.migrateIfNeeded()
        // 监视整个文件系统，使右键菜单在任何位置都可用。
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        diag("FinderSyncExt init; watching /")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        invocations.clear()
        diag("menu kind=\(String(describing: menuKind)) paths=\(urls.map(\.path).joined(separator: ", "))")
        let menu = NSMenu(title: AppBrand.displayName)
        // 关闭自动禁用：Finder Sync 上下文下 NSMenu 默认 autoenablesItems 会校验不到 target 而禁用菜单项，导致点击不触发 action。
        menu.autoenablesItems = false
        buildMenu(into: menu, urls: urls)
        return menu
    }

    private func buildMenu(into menu: NSMenu, urls: [URL]) {
        let state = ToolConfig.load()
        let applicable: [Tool] = ToolRegistry.shared.tools.filter { tool in
            (state.enabled[tool.id] ?? true) && tool.canPerform(on: urls)
        }

        if applicable.isEmpty {
            let placeholder = menu.addItem(withTitle: AppBrand.displayName, action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            return
        }

        if applicable.count == 1 {
            menu.addItem(menuItem(for: applicable[0], urls: urls))
            return
        }

        let parent = menu.addItem(withTitle: AppBrand.displayName, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: AppBrand.displayName)
        submenu.autoenablesItems = false
        for tool in applicable {
            submenu.addItem(menuItem(for: tool, urls: urls))
        }
        parent.submenu = submenu
    }

    private func menuItem(for tool: Tool, urls: [URL]) -> NSMenuItem {
        let item = NSMenuItem(title: tool.title, action: #selector(performTool(_:)), keyEquivalent: "")
        item.target = self
        // 用 tag 代替 representedObject（tag 跨进程保留，representedObject 不保留）。
        item.tag = invocations.append(ToolInvocation(toolId: tool.id, urls: urls))
        item.image = tool.image
        return item
    }

    @objc private func performTool(_ sender: NSMenuItem) {
        guard let invocation = invocations.resolve(tag: sender.tag) else {
            diag("performTool: 无法解析 tag=\(sender.tag)")
            return
        }
        diag("performTool id=\(invocation.toolId) paths=\(invocation.urls.map(\.path).joined(separator: ", "))")
        ToolDispatcher.perform(toolId: invocation.toolId, urls: invocation.urls)
        diag("performTool done id=\(invocation.toolId)")
    }

    /// 同时写 os_log 和容器内文件，便于外部读取诊断（os_log 在沙盒扩展里 log show 常抓不到）。
    private func diag(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let line = "\(Date())  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let file = ToolConfig.directoryURL.appendingPathComponent("diag.log")
        if FileManager.default.fileExists(atPath: file.path) {
            if let handle = FileHandle(forWritingAtPath: file.path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: file, options: .atomic)
        }
    }
}
