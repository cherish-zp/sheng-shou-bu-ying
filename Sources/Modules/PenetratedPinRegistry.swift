import Foundation

/// 贴图「鼠标穿透」登记表（纯逻辑）：登记处于穿透态的贴图（弱引用，
/// 贴图关闭后自动移出），F6 逃生通道按表恢复全部。
/// NSLock 保证跨线程访问安全（登记在主线程，热键恢复也回主线程，
/// 加锁只为防御未来调用方线程变化）。
public final class PenetratedPinRegistry {

    public static let shared = PenetratedPinRegistry()

    private let lock = NSLock()
    private let table = NSHashTable<AnyObject>.weakObjects()

    public init() {}

    /// 登记一张进入穿透态的贴图（弱引用，不延长生命周期）。
    public func add(_ entry: AnyObject) {
        lock.lock(); defer { lock.unlock() }
        table.add(entry)
    }

    /// 解除登记（恢复穿透或贴图关闭时）。
    public func remove(_ entry: AnyObject) {
        lock.lock(); defer { lock.unlock() }
        table.remove(entry)
    }

    /// 当前穿透态贴图数量。
    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return table.count
    }

    /// 当前全部穿透态贴图（无稳定顺序语义）。
    public var allEntries: [AnyObject] {
        lock.lock(); defer { lock.unlock() }
        return table.allObjects
    }

    /// 取出全部并清空（F6 恢复场景），返回登记时刻的快照。
    public func removeAllEntries() -> [AnyObject] {
        lock.lock(); defer { lock.unlock() }
        let all = table.allObjects
        table.removeAllObjects()
        return all
    }
}
