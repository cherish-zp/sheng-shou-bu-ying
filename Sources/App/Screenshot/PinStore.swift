import Foundation

/// AppKit 窗口的 App 级持有者。桌面贴图常驻桌面的语义要求其生命周期独立于单次截图
/// 会话的协调器——协调器每次 F1 都会重建，旧实例释放会连带释放全部在屏贴图
/// （bug：下一次 F1 清空所有贴图），故贴图由 ScreenshotModule 长期持有的 PinStore 托管。
final class PinStore<T: AnyObject> {
    private(set) var pins: [T] = []

    var isEmpty: Bool { pins.isEmpty }

    func add(_ pin: T) {
        pins.append(pin)
    }

    /// 按身份移除（同一窗口实例），未知实例为空操作。
    func remove(_ pin: T) {
        pins.removeAll { $0 === pin }
    }
}
