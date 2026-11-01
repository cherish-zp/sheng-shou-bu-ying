import Foundation

/// 系统热键注册器抽象。生产实现用 Carbon RegisterEventHotKey；测试用 fake。
public protocol HotkeyRegistrar: AnyObject {
    /// 系统热键触发时的回调，参数为注册时分配的 id。由 HotkeyManager 设置。
    var onTrigger: ((UInt32) -> Void)? { get set }
    /// 注册热键，返回是否成功。id 用于触发回调标识。
    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool
    /// 注销热键。
    func unregister(id: UInt32)
}

/// 热键管理器：把 Hotkey 绑定到 handler，处理冲突与分发。
public final class HotkeyManager {
    private let registrar: HotkeyRegistrar
    private var idToHandler: [UInt32: () -> Void] = [:]
    private var hotkeyToID: [Hotkey: UInt32] = [:]
    private var nextID: UInt32 = 1

    public init(registrar: HotkeyRegistrar) {
        self.registrar = registrar
        // 把系统触发桥接到 dispatch。
        registrar.onTrigger = { [weak self] id in self?.dispatch(id: id) }
    }

    /// 注册热键并绑定 handler。同一 Hotkey 重复注册或系统注册失败时返回 nil。
    @discardableResult
    public func register(_ hotkey: Hotkey, handler: @escaping () -> Void) -> UInt32? {
        if hotkeyToID[hotkey] != nil { return nil }
        let id = nextID
        nextID += 1
        guard registrar.register(id: id, keyCode: hotkey.keyCode, modifiers: hotkey.modifiers) else {
            return nil
        }
        idToHandler[id] = handler
        hotkeyToID[hotkey] = id
        return id
    }

    public func unregister(_ hotkey: Hotkey) {
        guard let id = hotkeyToID[hotkey] else { return }
        registrar.unregister(id: id)
        idToHandler.removeValue(forKey: id)
        hotkeyToID.removeValue(forKey: hotkey)
    }

    /// 系统热键触发时分发到对应 handler。
    public func dispatch(id: UInt32) {
        idToHandler[id]?()
    }

    /// 应用整套快捷键方案（Alt 主键体系）：先注销全部现有热键，再按方案注册。
    /// 冲突的绑定组不注册（进失败表）；系统级注册失败也进失败表——由 UI 提示，
    /// 此前失败只写日志、用户完全无感知。
    /// 返回失败表：功能 id → 解析出的 Hotkey。
    @discardableResult
    public func applyPreferences(_ preferences: HotkeyPreferences,
                                 handlers: [String: () -> Void]) -> [String: Hotkey] {
        for hotkey in hotkeyToID.keys { unregister(hotkey) }

        var failures: [String: Hotkey] = [:]
        let conflicted = Set(preferences.bindingConflictGroups().joined())
        for (id, _) in preferences.bindings.sorted(by: { $0.key < $1.key }) {
            guard let hotkey = preferences.hotkey(for: id) else { continue }
            if conflicted.contains(id) {
                failures[id] = hotkey
                continue
            }
            guard let handler = handlers[id] else { continue }   // 未装配的功能跳过，不算失败
            if register(hotkey, handler: handler) == nil {
                failures[id] = hotkey
            }
        }
        return failures
    }
}
