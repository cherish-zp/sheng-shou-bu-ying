import AppKit
import CoreGraphics
import Foundation

/// 最近一次成功截图的选区记录：rect 为该屏视图坐标（屏幕本地、左下原点），
/// displayID 用于跨会话定位同一块屏，screenPointSize 供重复时校验/换算参考。
public struct LastRegionRecord: Codable, Equatable {
    public let rect: CGRect
    public let displayID: CGDirectDisplayID
    public let screenPointSize: CGSize

    public init(rect: CGRect, displayID: CGDirectDisplayID, screenPointSize: CGSize) {
        self.rect = rect
        self.displayID = displayID
        self.screenPointSize = screenPointSize
    }
}

/// 上次截图区域持久化（UserDefaults）。纯逻辑、注入 UserDefaults 便于隔离单测。
public final class LastRegionStore {

    public static let defaultsKey = "screenshot.lastRegionRecord"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 记录最近一次成功截图的选区（覆盖式，只保留最近一条）。
    public func save(_ record: LastRegionRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// 读取记录；无记录或数据损坏返回 nil。
    public func load() -> LastRegionRecord? {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(LastRegionRecord.self, from: data)
    }

    /// 清除记录。
    public func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}

/// 显示器 ID → NSScreen 匹配。公共几何工具，截图协调器与重复区域控制器共用。
public enum ScreenDisplayMatcher {

    /// 按 CGDirectDisplayID 找对应 NSScreen；找不到（外接屏已拔）返回 nil。
    public static func screen(withDisplayID displayID: CGDirectDisplayID) -> NSScreen? {
        for screen in NSScreen.screens {
            let sid = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if sid == displayID { return screen }
        }
        return nil
    }
}
