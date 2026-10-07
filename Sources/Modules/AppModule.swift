import AppKit

/// App 级功能模块（截图/录屏/取色/OCR...），区别于 Finder 右键的 Tool。
/// 由菜单栏 App 或全局热键触发，运行在非沙盒 App 进程内。
public protocol AppModule: AnyObject {
    var id: String { get }
    var title: String { get }
    var defaultHotkey: Hotkey { get }
    func perform()
    /// 模块启用后启动常驻资源（全局监听等）。默认无操作。
    func start()
    /// 模块停用时释放常驻资源。默认无操作。
    func stop()
}

public extension AppModule {
    var image: NSImage? { nil }

    func start() {}
    func stop() {}
}
