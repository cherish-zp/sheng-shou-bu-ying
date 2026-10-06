import AppKit
import CoreGraphics

/// 录屏模块：F4 呼出 → 覆盖层选区（拖拽框选/点选窗口/Return 全屏）→ 红框 + 控制条
/// → 录制（RecordingEngine）→ 停止 → AVPlayer 预览 → 保存/复制/关闭。
/// 状态由 RecordingStateMachine 管理；F4 按键表见 RecordingKeyAction：
/// idle=呼出 / selecting|armed=取消选区 / recording|paused=停止 / stopped=不干预。
final class ScreenRecordingModule: NSObject, AppModule {

    let id = "screen-recording"
    let title = "录屏"
    let defaultHotkey = Hotkey.f4

    // MARK: - 依赖

    private let stateMachine = RecordingStateMachine()
    private let stopwatch = RecordingStopwatch()
    private let configStore = RecordingConfigStore()
    /// 设置页即时生效：每次开录时读取最新配置。
    private var config: RecordingConfig { configStore.load() }
    /// 实例化复用（只读使用，不修改）：截图捕获服务与统一反馈。
    private let captureService = ScreenCaptureService()
    private let feedback = ScreenshotFeedbackPresenter()

    // MARK: - 会话 UI 状态

    private var overlayWindows: [ScreenshotOverlayWindow] = []
    private var borderWindow: RecordingBorderWindow?
    private var controlBar: RecordingControlBar?
    private var previewPanel: RecordingPreviewPanel?
    private var previewURL: URL?
    private var engine: RecordingEngine?
    /// 已确认的选区（屏幕局部视图坐标）与所在屏幕。
    private var selectedRect: CGRect?
    private var selectedScreen: NSScreen?
    private var durationTimer: Timer?
    private var sessionLocalMonitor: Any?
    private var sessionGlobalMonitor: Any?
    private var previewEscMonitor: Any?

    /// 录制临时文件：~/Library/Application Support/mac_tool_pro/recording-tmp.mp4
    private var tempURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("mac_tool_pro", isDirectory: true)
            .appendingPathComponent("recording-tmp.mp4")
    }

    private enum Keys {
        static let esc: CGKeyCode = 53
        static let returnKey: CGKeyCode = 36
        static let keypadEnter: CGKeyCode = 76
    }

    // MARK: - AppModule

    func perform() {
        guard let action = RecordingKeyAction.action(for: stateMachine.state) else {
            DiagLog.write("ScreenRecording.perform ignored (state=\(stateMachine.state))")
            return
        }
        DiagLog.write("ScreenRecording.perform state=\(stateMachine.state) action=\(action)")
        switch action {
        case .beginSelection:   beginSelection()
        case .cancelSelection:  cancelSession()
        case .stop:             requestStop()
        }
    }

    // MARK: - 选区阶段

    private func beginSelection() {
        guard stateMachine.handle(.beginSelection) else { return }
        DiagLog.write("ScreenRecording.beginSelection")

        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            stateMachine.handle(.cancel)
            presentAlert(title: "需要屏幕录制权限",
                         message: "请在「系统设置 → 隐私与安全性 → 屏幕录制」中允许 mac_tool_pro 后重试。")
            return
        }
        cleanupSessionUI()

        // 预捕获画面（显示覆盖层之前），与截图流程同源
        let displays = captureService.captureAllDisplays()
        DiagLog.write("ScreenRecording precaptured \(displays.count) display(s)")
        guard !displays.isEmpty else {
            stateMachine.handle(.cancel)
            presentAlert(title: "无法开始录屏", message: "屏幕画面捕获失败，请检查屏幕录制权限。")
            return
        }
        NSApp.activate(ignoringOtherApps: true)

        overlayWindows = displays.compactMap { display -> ScreenshotOverlayWindow? in
            guard let screen = matchingScreen(displayID: display.displayID) else { return nil }
            let window = ScreenshotOverlayWindow(screen: screen, capturedImage: display.image)
            window.overlayView?.onSelectionComplete = { [weak self, weak window] rect in
                self?.confirmRegion(rect: rect, window: window)
            }
            window.overlayView?.onCancel = { [weak self] in
                self?.cancelSession()
            }
            window.orderFrontRegardless()
            return window
        }
        if let key = overlayWindows.first(where: { $0.screen == NSScreen.main }) ?? overlayWindows.first {
            key.makeKeyAndOrderFront(nil)
            key.makeFirstResponder(key.overlayView)
        }
        installSessionKeyMonitors()
    }

    /// 选区确认（拖拽完成 / 点选窗口）。进入 armed：收覆盖层、显红框与控制条。
    private func confirmRegion(rect: CGRect, window: ScreenshotOverlayWindow?) {
        guard let window = window, let screen = window.screen else { return }
        guard stateMachine.state == .selecting, stateMachine.handle(.regionConfirmed) else { return }
        DiagLog.write("ScreenRecording.regionConfirmed rect=\(rect) screen=\(screen.frame)")
        selectedRect = rect
        selectedScreen = screen

        // 收起覆盖层：录制的是真实画面，不能留遮罩
        for w in overlayWindows { w.orderOut(nil) }
        overlayWindows.removeAll()

        // 红色录屏边框（全局坐标 = 屏幕 origin + 选区 origin）
        let globalRect = CGRect(
            x: screen.frame.origin.x + rect.origin.x,
            y: screen.frame.origin.y + rect.origin.y,
            width: rect.width, height: rect.height)
        borderWindow = RecordingBorderWindow(globalRect: globalRect)

        // 悬浮控制条（选区下方，ToolbarPositioner 同款定位）
        let bar = RecordingControlBar()
        bar.onStart = { [weak self] in self?.startRecording() }
        bar.onTogglePause = { [weak self] in self?.togglePause() }
        bar.onStop = { [weak self] in self?.requestStop() }
        bar.onCancel = { [weak self] in self?.cancelSession() }
        controlBar = bar
        let origin = ToolbarPositioner.position(
            forSelection: rect, toolbarSize: bar.frame.size, screenFrame: screen.frame)
        bar.showArmed(at: origin)
    }

    /// 选区阶段按 Return：以按键覆盖层所在屏幕的整屏为录制区（全屏一键）。
    private func confirmFullScreen() {
        guard let window = overlayWindows.first(where: { $0.isKeyWindow }) ?? overlayWindows.first,
              let view = window.overlayView else { return }
        confirmRegion(rect: view.bounds, window: window)
    }

    // MARK: - 录制阶段

    private func startRecording() {
        guard stateMachine.state == .armed, stateMachine.handle(.start) else { return }
        guard let rect = selectedRect, let screen = selectedScreen else {
            stateMachine.handle(.cancel)
            cleanupSessionUI()
            return
        }
        DiagLog.write("ScreenRecording.startRecording rect=\(rect)")

        let scale = screen.backingScaleFactor
        let displayPixelSize = CGSize(width: screen.frame.width * scale,
                                      height: screen.frame.height * scale)
        let pixelRect = RecordingGeometry.pixelRect(
            forSelection: rect, screenHeightPoints: screen.frame.height,
            scale: scale, displayPixelSize: displayPixelSize)
        let sourceRect = RecordingGeometry.sourceRectPoints(fromPixelRect: pixelRect, scale: scale)

        let cfg = config
        let engine = RecordingEngine()
        engine.onFinished = { [weak self] result in
            self?.engineDidFinish(result)
        }
        self.engine = engine
        stopwatch.start()
        engine.start(RecordingEngine.StartParams(
            displayID: displayID(of: screen),
            sourceRectPoints: sourceRect,
            outputPixelSize: pixelRect.size,
            frameRate: cfg.frameRate.rawValue,
            systemAudioEnabled: cfg.systemAudioEnabled,
            microphoneEnabled: cfg.microphoneEnabled,
            outputURL: tempURL))

        // 控制条切换到录制形态（原位，不重新定位）
        controlBar?.showRecording(at: controlBar?.frame.origin ?? .zero)
        startDurationTimer()
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.controlBar?.updateDuration(RecordingDurationFormatter.format(self.stopwatch.elapsed))
        }
        RunLoop.main.add(timer, forMode: .common)
        durationTimer = timer
    }

    private func togglePause() {
        switch stateMachine.state {
        case .recording:
            guard stateMachine.handle(.pause) else { return }
            engine?.pause()
            stopwatch.pause()
            controlBar?.setPaused(true)
            DiagLog.write("ScreenRecording.paused elapsed=\(stopwatch.elapsed)")
        case .paused:
            guard stateMachine.handle(.resume) else { return }
            engine?.resume()
            stopwatch.resume()
            controlBar?.setPaused(false)
            DiagLog.write("ScreenRecording.resumed elapsed=\(stopwatch.elapsed)")
        default:
            break
        }
    }

    private func requestStop() {
        guard stateMachine.handle(.stop) else { return }
        DiagLog.write("ScreenRecording.requestStop elapsed=\(stopwatch.elapsed)")
        durationTimer?.invalidate()
        durationTimer = nil
        controlBar?.orderOut(nil)
        borderWindow?.orderOut(nil)
        engine?.finish(discard: false)
    }

    /// 引擎收尾回调（主线程）：成功弹预览，失败/取消走清理。
    private func engineDidFinish(_ result: Result<URL, Error>) {
        engine = nil
        switch result {
        case .success(let url):
            DiagLog.write("ScreenRecording.engineFinished url=\(url.path)")
            removeSessionKeyMonitors()
            borderWindow?.orderOut(nil)
            borderWindow = nil
            controlBar?.orderOut(nil)
            controlBar = nil
            showPreview(url: url)
        case .failure(let error):
            if let engineError = error as? RecordingEngine.EngineError, engineError == .cancelled {
                DiagLog.write("ScreenRecording.engineFinished: cancelled by user")
            } else {
                DiagLog.write("ScreenRecording.engineFinished error: \(error)")
                presentAlert(title: "录屏失败", message: error.localizedDescription)
            }
            teardownToIdle()
        }
    }

    // MARK: - 取消与清理

    /// 整体取消（ESC / 控制条 ✕ / F4 非录制态）。录制中丢弃临时文件。
    private func cancelSession() {
        let state = stateMachine.state
        guard RecordingStateMachine.acceptsCancel(state) else { return }
        DiagLog.write("ScreenRecording.cancelSession from=\(state)")
        _ = stateMachine.handle(.cancel)

        if state == .stopped {
            // 预览期取消 = 关闭预览并删除临时文件
            closePreview()
            return
        }
        if state == .recording || state == .paused {
            engine?.finish(discard: true)
        }
        teardownToIdle()
    }

    /// 会话收尾回 idle：清 UI、清监听、复位计时。
    private func teardownToIdle() {
        durationTimer?.invalidate()
        durationTimer = nil
        for w in overlayWindows { w.orderOut(nil) }
        overlayWindows.removeAll()
        borderWindow?.orderOut(nil)
        borderWindow = nil
        controlBar?.orderOut(nil)
        controlBar = nil
        removeSessionKeyMonitors()
        removePreviewEscMonitor()
        selectedRect = nil
        selectedScreen = nil
        stopwatch.reset()
    }

    /// 选区开始前的残留清理（不影响预览窗）。
    private func cleanupSessionUI() {
        for w in overlayWindows { w.orderOut(nil) }
        overlayWindows.removeAll()
        borderWindow?.orderOut(nil)
        borderWindow = nil
        controlBar?.orderOut(nil)
        controlBar = nil
        removeSessionKeyMonitors()
    }

    // MARK: - 预览与输出

    private func showPreview(url: URL) {
        previewURL = url
        let panel = RecordingPreviewPanel(fileURL: url)
        panel.onSave = { [weak self] in self?.saveRecording() }
        panel.onCopy = { [weak self] in self?.copyRecording() }
        panel.onClose = { [weak self] in self?.closePreview() }
        previewPanel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installPreviewEscMonitor()
        DiagLog.write("ScreenRecording.preview shown")
    }

    /// 保存：确保目录存在 → 去重命名 → 移动临时文件 → Toast（可点击 Finder 定位）。
    private func saveRecording() {
        guard let url = previewURL else { return }
        do {
            let dir = RecordingConfig.defaultSaveDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            let name = RecordingFileNameBuilder.uniqueFileName(date: Date(), existingNames: existing)
            let destination = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: url, to: destination)
            DiagLog.write("ScreenRecording.saved: \(destination.path)")
            feedback.showSaved(url: destination)
            closePreview()
        } catch {
            DiagLog.write("ScreenRecording.save failed: \(error)")
            presentAlert(title: "保存失败", message: error.localizedDescription)
        }
    }

    /// 复制：MP4 文件 fileURL 写剪贴板（关闭预览前文件一直有效）。
    private func copyRecording() {
        guard let url = previewURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let ok = pasteboard.writeObjects([url as NSURL])
        DiagLog.write("ScreenRecording.copied ok=\(ok)")
        if ok { feedback.showCopied() }
    }

    /// 关闭预览：删除临时文件，状态回 idle。
    private func closePreview() {
        removePreviewEscMonitor()
        previewPanel?.stopPlayback()
        previewPanel?.orderOut(nil)
        previewPanel = nil
        if let url = previewURL {
            try? FileManager.default.removeItem(at: url)
            previewURL = nil
        }
        if stateMachine.state == .stopped {
            _ = stateMachine.handle(.cancel)
        }
        selectedRect = nil
        selectedScreen = nil
        stopwatch.reset()
        DiagLog.write("ScreenRecording.preview closed")
    }

    // MARK: - 按键监听

    /// 会话期按键：本地（我们窗口为 key 时，可消费）+ 全局（用户在其他 App 中，仅观察）。
    /// ESC = 取消；Return/小键盘 Enter = 选区阶段全屏、armed 开始录制。
    private func installSessionKeyMonitors() {
        removeSessionKeyMonitors()
        sessionLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == Keys.esc, RecordingStateMachine.acceptsCancel(self.stateMachine.state) {
                DiagLog.write("ScreenRecording ESC (local)")
                self.cancelSession()
                return nil
            }
            if self.isEnterKey(event.keyCode), self.handleEnter() {
                return nil
            }
            return event
        }
        sessionGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            if event.keyCode == Keys.esc, RecordingStateMachine.acceptsCancel(self.stateMachine.state) {
                DiagLog.write("ScreenRecording ESC (global)")
                self.cancelSession()
                return
            }
            if self.isEnterKey(event.keyCode) {
                _ = self.handleEnter()
            }
        }
        DiagLog.write("ScreenRecording key monitors installed (local+global)")
    }

    private func removeSessionKeyMonitors() {
        if let monitor = sessionLocalMonitor {
            NSEvent.removeMonitor(monitor)
            sessionLocalMonitor = nil
        }
        if let monitor = sessionGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            sessionGlobalMonitor = nil
        }
    }

    private func isEnterKey(_ keyCode: CGKeyCode) -> Bool {
        keyCode == Keys.returnKey || keyCode == Keys.keypadEnter
    }

    /// Return 键处理。返回是否消费。
    private func handleEnter() -> Bool {
        switch stateMachine.state {
        case .selecting:
            confirmFullScreen()
            return true
        case .armed:
            startRecording()
            return true
        default:
            return false
        }
    }

    /// 预览期 ESC 关闭（仅本地：预览窗为 key 窗口）。
    private func installPreviewEscMonitor() {
        removePreviewEscMonitor()
        previewEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.keyCode == Keys.esc else { return event }
            self.closePreview()
            return nil
        }
    }

    private func removePreviewEscMonitor() {
        if let monitor = previewEscMonitor {
            NSEvent.removeMonitor(monitor)
            previewEscMonitor = nil
        }
    }

    // MARK: - 辅助

    private func matchingScreen(displayID: CGDirectDisplayID) -> NSScreen? {
        for screen in NSScreen.screens {
            let sid = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if sid == displayID { return screen }
        }
        return NSScreen.screens.first
    }

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
            ?? CGMainDisplayID()
    }

    /// 同风格错误弹窗（层级抬到 screenSaver+3，避免被覆盖层遮挡）。
    private func presentAlert(title: String, message: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "好")
            alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
            alert.runModal()
        }
    }
}
