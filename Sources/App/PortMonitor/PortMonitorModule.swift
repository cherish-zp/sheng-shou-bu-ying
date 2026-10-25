import AppKit

/// 端口占用模块：F2 / 菜单点击打开占用窗口。
final class PortMonitorModule: NSObject, AppModule {
    let id = "portMonitor"
    let title = "端口占用"
    /// 不注册全局热键：功能键已全部占用（F2 归中转站），经菜单「端口占用…」触发。
    let defaultHotkey: Hotkey? = nil

    private let queryService = PortQueryService()
    private let killService = PortKillService()
    private var windowController: PortListWindowController?

    func perform() {
        let controller = windowController ?? PortListWindowController(
            queryService: queryService, killService: killService)
        windowController = controller
        controller.showAndRefresh()
    }

    func stop() {
        // 模块停用：收起窗口（重新启用后菜单/热键可再呼出）
        windowController?.window.orderOut(nil)
    }
}
