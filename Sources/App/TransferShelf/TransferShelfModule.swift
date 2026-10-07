import AppKit

/// 文件中转模块：菜单栏可开关；拖拽文件时顶部面板自动出现，F2 手动呼出。
/// AppModule 生命周期（start/stop）由 AppDelegate 在模块开关特判处调用；
/// start/stop 已提升为协议要求（其他模块走默认空实现）。
final class TransferShelfModule: AppModule {

    let id = "transfer-shelf"
    let title = "文件中转"
    /// F2 = kVK_F2(120)，手动呼出中转面板。
    let defaultHotkey = Hotkey(keyCode: 120)

    /// 模块自有控制器实例（去全局单例；视图层经闭包回调到控制器）。
    private let controller = TransferShelfPanelController()
    private let monitor = MouseDragMonitor()

    /// 手动触发（F2 / 菜单模块项）。
    func perform() {
        controller.showPanel(manual: true)
    }

    /// 开启全局拖拽监听。
    func start() {
        let controller = self.controller
        monitor.start(
            onDragStart: { [weak controller] in controller?.dragSessionStarted() },
            onDragEnd: { [weak controller] in controller?.dragSessionEnded() },
            onHotZoneHover: { [weak controller] in controller?.hotZoneHovered() }
        )
    }

    /// 停止监听并收起面板资源：停用模块后面板/热区/调度不得残留。
    func stop() {
        monitor.stop()
        controller.deactivate()
    }
}
