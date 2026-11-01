import Foundation

/// App 模块注册表：登记模块、管理启用状态。
/// 热键注册已统一迁移到 HotkeyManager.applyPreferences（Alt 主键方案），
/// 注册表只管启用状态——热键 handler 内部按 isEnabled 过滤。
public final class AppModuleRegistry {
    public private(set) var modules: [AppModule] = []
    private var enabled: [String: Bool] = [:]
    private let hotkeyManager: HotkeyManager
    private let configStore: ModuleConfigStore

    public init(hotkeyManager: HotkeyManager, configDefaults: UserDefaults = .standard) {
        self.hotkeyManager = hotkeyManager
        self.configStore = ModuleConfigStore(defaults: configDefaults)
        self.enabled = configStore.load().enabled
    }

    public func register(_ module: AppModule) {
        modules.append(module)
    }

    public func module(for id: String) -> AppModule? {
        modules.first { $0.id == id }
    }

    public func isEnabled(_ id: String) -> Bool {
        enabled[id] ?? true
    }

    public func setEnabled(_ id: String, _ on: Bool) {
        enabled[id] = on
        configStore.save(ModuleConfigState(enabled: enabled))
    }
}
