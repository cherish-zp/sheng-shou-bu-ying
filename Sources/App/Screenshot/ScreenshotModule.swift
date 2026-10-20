import AppKit

/// 截图模块：AppModule 的第一个实现。
/// F1 触发 -> 启动 ScreenshotCoordinator 进入选区模式。
/// 使用 ScreenshotSession 防止重复触发导致覆盖层叠加。
final class ScreenshotModule: AppModule {
    let id = "screenshot"
    let title = "截图"
    let defaultHotkey: Hotkey? = .f1

    let session = ScreenshotSession()
    /// 贴图 App 级持有：跨协调器会话存活（协调器每次 F1 重建，贴图不能跟着释放）
    private let pinStore = PinStore<PinWindow>()
    private var coordinator: ScreenshotCoordinator?

    func perform() {
        // 防止重复触发：会话活跃时直接忽略
        guard session.start() else {
            DiagLog.write("ScreenshotModule.perform() ignored - session already active")
            return
        }
        DiagLog.write("ScreenshotModule.perform() called")

        // 先结束旧的协调器（清理残留窗口）
        coordinator?.finish()

        let coord = ScreenshotCoordinator(pinStore: pinStore)
        coord.onFinished = { [weak self] in
            self?.session.finish()
        }
        self.coordinator = coord
        coord.start()
    }

    /// 贴图当前选区（F3 触发）。仅截图会话活跃时生效。
    /// 返回 true 表示已处理（消费按键），false 表示无活跃会话（放行按键）。
    @discardableResult
    func pin() -> Bool {
        guard session.state == .active else {
            DiagLog.write("ScreenshotModule.pin() ignored - no active session")
            return false
        }
        coordinator?.pinCurrentSelection()
        return true
    }
}
