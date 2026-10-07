import Foundation

/// Persists per-tool enabled state to a JSON file shared between the main app and
/// the Finder Sync extension (both non-sandboxed, same user account).
public enum ToolConfig {
    public struct State: Codable {
        public var enabled: [String: Bool]
        public init(enabled: [String: Bool] = [:]) {
            self.enabled = enabled
        }
    }

    public static var directoryURL: URL {
        let dir = AppSupportDirectory.url
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var fileURL: URL {
        directoryURL.appendingPathComponent("config.json")
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
