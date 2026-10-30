import Foundation

/// iCloud 键值同步（NSUbiquitousKeyValueStore，1MB 上限）：只同步收藏类轻量数据。
/// 需要在签名团队下开启 iCloud 能力（project.yml entitlements）；未开启时静默失败。
public enum CloudSync {
    private static let store = NSUbiquitousKeyValueStore.default

    public static func syncFavorites(_ payload: String, forKey key: String) {
        store.set(payload, forKey: key)
        store.synchronize()
    }

    public static func loadFavorites(forKey key: String) -> String? {
        store.string(forKey: key)
    }

    /// 外部变更通知订阅（返回通知名）。
    public static var changeNotification: Notification.Name {
        NSUbiquitousKeyValueStore.didChangeExternallyNotification
    }
}
