import Foundation

/// App 模块启用状态：跨 App 启动保留用户关闭的功能模块。
public struct ModuleConfigState: Codable, Equatable {
    public var enabled: [String: Bool]

    public init(enabled: [String: Bool] = [:]) {
        self.enabled = enabled
    }
}

public struct ModuleConfigStore {
    static let storageKey = "appModuleConfig"

    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ModuleConfigState {
        guard let data = defaults.data(forKey: Self.storageKey),
              let state = try? JSONDecoder().decode(ModuleConfigState.self, from: data) else {
            return ModuleConfigState()
        }
        return state
    }

    public func save(_ state: ModuleConfigState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
