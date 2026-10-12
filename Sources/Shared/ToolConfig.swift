import Foundation

/// Persists per-tool enabled state, shared between the main app and the Finder Sync
/// extension. 扩展（沙盒）读自身容器；App（非沙盒）直写扩展容器内同一文件——
/// 两进程必须落在同一物理路径，否则设置面板的工具开关对扩展无效（split-brain）。
public enum ToolConfig {
    public struct State: Codable {
        public var enabled: [String: Bool]
        public init(enabled: [String: Bool] = [:]) {
            self.enabled = enabled
        }
    }

    /// 按进程角色解析共享配置目录：
    /// - 扩展进程（沙盒）：自身 Application Support/圣手捕影（容器内）；
    /// - App 进程（非沙盒）：直写扩展容器内同名目录（扩展读不到 App 自身的目录）。
    public static func resolveDirectoryURL(isExtensionProcess: Bool, homeDirectory: URL) -> URL {
        guard isExtensionProcess else {
            return homeDirectory
                .appendingPathComponent("Library/Containers/\(IPCConfig.extensionBundleID)/Data/Library/Application Support/\(AppSupportDirectory.currentName)", isDirectory: true)
        }
        return homeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(AppSupportDirectory.currentName, isDirectory: true)
    }

    public static var directoryURL: URL {
        let dir = resolveDirectoryURL(
            isExtensionProcess: Bundle.main.bundlePath.hasSuffix(".appex"),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var fileURL: URL {
        directoryURL.appendingPathComponent("config.json")
    }

    /// 一次性迁移（App 进程调用）：沙盒化之前 ToolConfig 写在 App 自身的 App Support，
    /// 扩展读不到；把旧 config.json 并入扩展容器。容器已有配置（扩展可能已写入）时
    /// 保留现有版本、旧文件原地保留不删；幂等，失败不丢数据。
    /// - Returns: 是否发生了搬移。
    @discardableResult
    public static func migrateLegacyConfigIfNeeded(
        legacyFileURL: URL,
        destinationFileURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: legacyFileURL.path) else { return false }
        try? fileManager.createDirectory(
            at: destinationFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: destinationFileURL.path) else { return false }
        do {
            try fileManager.moveItem(at: legacyFileURL, to: destinationFileURL)
            return true
        } catch {
            NSLog("[ToolConfig] 迁移旧配置失败（原文件保留）: \(error.localizedDescription)")
            return false
        }
    }

    public static func load() -> State {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(State.self, from: data) else {
            return State()
        }
        return state
    }

    public static func save(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Defaults to enabled when unset.
    public static func isEnabled(_ id: String) -> Bool {
        load().enabled[id] ?? true
    }

    public static func setEnabled(_ id: String, _ enabled: Bool) {
        var state = load()
        state.enabled[id] = enabled
        save(state)
    }
}
