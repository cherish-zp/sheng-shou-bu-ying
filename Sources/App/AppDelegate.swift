import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var requestProcessor: RequestProcessor?
    private var pollTimer: Timer?

    // App 模块（截图/录屏/取色/OCR...）
    private var hotkeyManager: HotkeyManager!
    private var moduleRegistry: AppModuleRegistry!
    private var screenshotModule: ScreenshotModule!
    private var transferShelfModule: TransferShelfModule!
    private var globalKeyMonitor: Any?
    private var eventTapListener: CGEventTapHotkeyListener?
    private var permissionTimer: Timer?
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 支持目录迁移（mac_tool_pro → 圣手捕影）必须最先执行，任何数据读取都在其后
        AppSupportDirectory.migrateIfNeeded()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let statusImage = NSImage(named: "MenuBarIcon") {
            statusImage.isTemplate = true
            statusItem.button?.image = statusImage
        } else { // 资产缺失时兜底系统符号
            statusItem.button?.image = NSImage(
                systemSymbolName: "hammer",
                accessibilityDescription: AppBrand.displayName
            )
            statusItem.button?.image?.isTemplate = true
        }

        setupAppModules()

        // 调试用：监听分布式通知触发截图（可从命令行触发）
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(triggerScreenshot),
            name: NSNotification.Name("com.zp.shengshoubuying.trigger-screenshot"), object: nil
        )
        // 诊断用：导出 App 捕获与系统 screencapture 参照图，对照定位捕获侧色差
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(dumpCaptureReference),
            name: NSNotification.Name("com.zp.shengshoubuying.dump-capture"), object: nil
        )
        setupMainMenu()
        setupGlobalKeyMonitor()
        rebuildMenu()
        startRequestPolling()

        // 片段数据变更时重建菜单（添加/删除/保存后菜单栏同步刷新）
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildMenuFromNotification),
            name: .snippetsDidChange, object: nil
        )
    }

    @objc private func rebuildMenuFromNotification() {
        rebuildMenu()
    }

    /// 构建主菜单：菜单栏应用默认无主菜单，导致 NSTextView/NSTextField
    /// 无法响应 Cmd+V/C/X/A/Z。此处添加「编辑」子菜单修复粘贴等快捷键。
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App 菜单（必须存在，否则系统不显示主菜单）
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 \(AppBrand.displayName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // 编辑菜单（Cut/Copy/Paste/SelectAll/Undo/Redo）
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu()
        editMenu.title = "编辑"
        for spec in EditMenuSpec.editMenuItems {
            editMenu.addItem(withTitle: spec.title,
                             action: NSSelectorFromString(spec.action),
                             keyEquivalent: spec.keyEquivalent)
        }
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    /// 初始化 App 模块注册表 + Carbon 全局热键。
    private func setupAppModules() {
        let registrar = CarbonHotkeyRegistrar()
        hotkeyManager = HotkeyManager(registrar: registrar)
        moduleRegistry = AppModuleRegistry(hotkeyManager: hotkeyManager)

        screenshotModule = ScreenshotModule()
        moduleRegistry.register(screenshotModule)

        transferShelfModule = TransferShelfModule()
        moduleRegistry.register(transferShelfModule)
        if moduleRegistry.isEnabled(transferShelfModule.id) {
            transferShelfModule.start()
        }

        moduleRegistry.register(ScreenRecordingModule())
        moduleRegistry.register(ColorPickerModule())
    }

    /// 热键监听：三层兜底确保 F1 能触发截图。
    /// 1. CGEventTap（主）：可消费事件、阻止系统功能键拦截，需辅助功能权限
    /// 2. NSEvent 全局监控（备）：Carbon 不触发时兜底
    /// 3. Carbon RegisterEventHotKey（已在 AppModuleRegistry 注册）
    private func setupGlobalKeyMonitor() {
        // 检查并请求辅助功能权限（CGEventTap 和全局键盘监控需要）
        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        DiagLog.write("Accessibility trusted: \(trusted)")

        tryStartEventTap()

        // NSEvent 全局监控备选方案
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if ScreenshotHotkeyAction.action(for: UInt32(event.keyCode)) == .screenshot,
               self?.moduleRegistry.isEnabled("screenshot") == true {
                DiagLog.write("NSEvent global monitor: F1 detected")
                self?.triggerScreenshot()
            }
        }
        DiagLog.write("Hotkey listeners installed (CGEventTap + NSEvent monitor) for F1+F3")

        // 如果权限未授予，启动定时器等待用户授权后自动重建 CGEventTap
        if !trusted {
            startPermissionRecoveryTimer()
        }
    }

    /// 尝试创建 CGEventTap，成功返回 true。
    @discardableResult
    private func tryStartEventTap() -> Bool {
        let tapListener = CGEventTapHotkeyListener()
        tapListener.start(keyCodes: [122, 99]) { [weak self] keyCode in
            guard let self = self else { return false }
            switch ScreenshotHotkeyAction.action(for: UInt32(keyCode)) {
            case .screenshot:
                // F1：仅模块启用时消费并触发截图
                guard self.moduleRegistry.isEnabled("screenshot") else { return false }
                self.triggerScreenshot()
                return true
            case .pin:
                // F3：仅在截图会话活跃时消费并贴图，否则放行给系统
                if self.screenshotModule.pin() {
                    return true
                }
                return false
            case nil:
                return false
            }
        }
        // start() 内部会记录成功/失败日志
        eventTapListener = tapListener
        return AXIsProcessTrusted()
    }

    /// 定时检查辅助功能权限，授予后自动重建 CGEventTap。
    private func startPermissionRecoveryTimer() {
        DiagLog.write("Starting permission recovery timer (waiting for Accessibility)")
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                DiagLog.write("Accessibility permission granted! Rebuilding CGEventTap")
                timer.invalidate()
                self.permissionTimer = nil
                self.tryStartEventTap()
            }
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = menu.addItem(withTitle: AppBrand.displayName, action: nil, keyEquivalent: "")
        header.isEnabled = false

        // App 模块
        menu.addItem(.separator())
        let modulesHeader = menu.addItem(withTitle: "功能模块", action: nil, keyEquivalent: "")
        modulesHeader.isEnabled = false
        for module in moduleRegistry.modules {
            let hotkeySuffix = module.defaultHotkey.functionKeyLabel.map { " (\($0))" } ?? ""
            let item = NSMenuItem(title: module.title + hotkeySuffix, action: #selector(performModule(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = module.id
            item.isEnabled = moduleRegistry.isEnabled(module.id)
            item.state = .off
            menu.addItem(item)
        }

        // 重复上次截图区域（对新鲜屏幕帧重截并复制，无覆盖层）
        menu.addItem(.separator())
        let repeatItem = NSMenuItem(title: "重复上次截图区域", action: #selector(repeatLastRegion), keyEquivalent: "")
        repeatItem.target = self
        repeatItem.isEnabled = moduleRegistry.isEnabled("screenshot")
        menu.addItem(repeatItem)

        // 快速片段
        menu.addItem(.separator())
        let snippetsHeader = menu.addItem(withTitle: "快速片段", action: nil, keyEquivalent: "")
        snippetsHeader.isEnabled = false
        let snippetManager = SnippetManager.shared
        if snippetManager.snippets.isEmpty {
            let emptyItem = menu.addItem(withTitle: "（暂无片段）", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
        } else {
            for snippet in snippetManager.snippets {
                let item = NSMenuItem(title: snippet.key, action: #selector(copySnippet(_:)), keyEquivalent: "")
                item.target = self
                item.toolTip = snippet.content
                menu.addItem(item)
            }
        }
        menu.addItem(withTitle: "管理片段...", action: #selector(showSnippetSettings), keyEquivalent: "")

        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "退出 \(AppBrand.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    /// 轮询扩展容器里的"新建文件"请求队列，由本非沙盒进程真正创建文件。
    private func startRequestPolling() {
        requestProcessor = RequestProcessor(queueDirectory: IPCConfig.extensionRequestDirectory())
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.requestProcessor?.processAll()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    @objc private func performModule(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        guard moduleRegistry.isEnabled(id) else { return }
        moduleRegistry.module(for: id)?.perform()
    }

    private func handleModuleStateChanged(id: String, isEnabled: Bool) {
        if id == transferShelfModule.id {
            if isEnabled {
                transferShelfModule.start()
            } else {
                transferShelfModule.stop()
            }
        }
        rebuildMenu()
    }

    @objc private func triggerScreenshot() {
        guard moduleRegistry.isEnabled("screenshot") else { return }
        // ScreenshotModule 内部用 ScreenshotSession 防止重复触发
        screenshotModule.perform()
    }

    /// 菜单栏「重复上次截图区域」：无记录/捕获失败时 beep 提示（控制器内部已记 diag.log）。
    @objc private func repeatLastRegion() {
        if !LastRegionRepeatController.shared.repeatAndCopy() {
            NSSound.beep()
        }
    }

    /// 诊断：同一时刻分别用 App 捕获路径（CGDisplayCreateImage）与系统
    /// /usr/sbin/screencapture（Cmd+Shift+4 同源，色调映射正确）导出全屏图到 /tmp，
    /// 对照两者的上下带亮度即可判定纵向渐变是否来自 CGDisplayCreateImage。
    @objc private func dumpCaptureReference() {
        let service = ScreenCaptureService()
        for (id, image, _) in service.captureAllDisplays() {
            let rep = NSBitmapImageRep(cgImage: image)
            if let data = rep.representation(using: .png, properties: [:]) {
                let url = URL(fileURLWithPath: "/tmp/mtg_cap_\(id).png")
                try? data.write(to: url)
            }
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-x", "/tmp/mtg_ref_1.png", "/tmp/mtg_ref_2.png"]
        try? proc.run()
        proc.waitUntilExit()
        DiagLog.write("DumpCaptureReference done exit=\(proc.terminationStatus)")
    }

    // MARK: - 快速片段

    @objc private func copySnippet(_ sender: NSMenuItem) {
        let key = sender.title
        if SnippetManager.shared.copyToPasteboard(forKey: key) {
            DiagLog.write("Snippet copied: \(key)")
            CopyToastPresenter.shared.show()
        }
    }

    @objc private func showSettings() {
        openSettings(category: 0)
    }

    /// Dock 图标点击 / 系统重开事件：仅激活应用，不弹任何窗口。
    /// 设置窗口的唯一入口是菜单栏「设置…（⌘,）」。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    @objc private func showSnippetSettings() {
        openSettings(category: 1)
    }

    private func openSettings(category: Int) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(
                moduleRegistry: moduleRegistry,
                onModuleStateChanged: { [weak self] id, isEnabled in
                    self?.handleModuleStateChanged(id: id, isEnabled: isEnabled)
                }
            )
        }
        settingsWindow?.showAndFocus(category: category)
    }
}
