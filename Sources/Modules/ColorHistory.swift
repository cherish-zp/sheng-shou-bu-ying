import Foundation

/// 取色历史（纯逻辑）：容量截断 + 连续重复项去重。
/// 取色器模块内存保留最近 5 次取色（#RRGGBB），不落盘；v1 无 UI，
/// 供未来挂到菜单展示（模块暴露 entries 只读数组）。
public final class ColorHistory {

    public let capacity: Int
    public private(set) var entries: [String] = []

    public init(capacity: Int = 5) {
        self.capacity = Swift.max(1, capacity)
    }

    public var count: Int { entries.count }

    /// 记录一次取色：与上一条相同则忽略（连续重复去重）；
    /// 超出容量丢弃最旧条目。
    public func record(_ hex: String) {
        guard !hex.isEmpty else { return }
        if entries.last == hex { return }
        entries.append(hex)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// 清空历史。
    public func removeAll() {
        entries.removeAll()
    }
}
