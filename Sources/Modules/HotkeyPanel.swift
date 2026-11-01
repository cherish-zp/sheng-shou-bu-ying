import Foundation

/// 浮引快捷键面板纯逻辑：键位字符→键码对照、浮引键盘布局行序、应用启动绑定存储、
/// 面板键位合并视图。副作用（窗口、热键注册、App 启动）在 App 层 HotkeyPanelModule。

/// 键位字符 → Carbon 虚拟键码对照（HIToolbox kVK_ANSI_*，浮引键盘布局）。
/// 数字行 1=18…0=29、-=27、==24；字母按 Q/A/Z 三排。
public enum HotkeyPanelKeyCodes {

    /// 键位字符（大写）→ 键码。
    public static let keyCodes: [Character: UInt32] = [
        // 数字行
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26,
        "8": 28, "9": 25, "0": 29, "-": 27, "=": 24,
        // Q 行
        "Q": 12, "W": 13, "E": 14, "R": 15, "T": 17, "Y": 16, "U": 32,
        "I": 34, "O": 31, "P": 35,
        // A 行
        "A": 0, "S": 1, "D": 2, "F": 3, "G": 5, "H": 4, "J": 38, "K": 40, "L": 37,
        // Z 行
        "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "N": 45, "M": 46,
    ]

    /// 键位字符 → 键码（大小写不敏感）。
    public static func keyCode(for keyChar: Character) -> UInt32? {
        keyCodes[Character(keyChar.uppercased())]
    }
}

/// 浮引键盘布局：渲染顺序与浮引一致（数字行 → Q 行 → A 行 → Z 行）。
public enum HotkeyPanelLayout {

    public static let rows: [[Character]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
    ]
}

/// 应用启动绑定：把某个已安装应用绑到面板键位（⌥+键位 全局直达启动）。
public struct AppLaunchBinding: Codable, Equatable {
    public var bundleID: String
    public var name: String
    public var keyCode: UInt32
    public var usesShift: Bool

    public init(bundleID: String, name: String, keyCode: UInt32, usesShift: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.keyCode = keyCode
        self.usesShift = usesShift
    }
}

/// 应用启动绑定存储：同键位覆盖、按 bundleID 移除、与功能绑定冲突检测。
public struct AppLaunchBindingStore: Codable, Equatable {

    public var bindings: [AppLaunchBinding]

    public init(bindings: [AppLaunchBinding] = []) {
        self.bindings = bindings
    }

    /// 新增绑定：同一键码只保留一条（后写覆盖先写）。
    public mutating func add(_ binding: AppLaunchBinding) {
        bindings.removeAll { $0.keyCode == binding.keyCode }
        bindings.append(binding)
    }

    /// 移除某应用的全部绑定。
    public mutating func remove(bundleID: String) {
        bindings.removeAll { $0.bundleID == bundleID }
    }

    /// 按键码查询绑定。
    public func binding(forKeyCode keyCode: UInt32) -> AppLaunchBinding? {
        bindings.first { $0.keyCode == keyCode }
    }

    /// 与功能绑定冲突的应用绑定（同键码 + 同 shift，等价于同一 HotkeyBinding）。
    public func conflicts(with prefs: HotkeyPreferences) -> [AppLaunchBinding] {
        let functionBindings = prefs.bindings.values
        return bindings.filter { app in
            functionBindings.contains {
                $0.keyCode == app.keyCode && $0.usesShift == app.usesShift
            }
        }
    }
}

// MARK: - UserDefaults 持久化

public extension AppLaunchBindingStore {
    static let defaultsKey = "appLaunchBindings"

    /// 读取已保存绑定；缺失/损坏时返回空表。
    static func load(defaults: UserDefaults = .standard) -> AppLaunchBindingStore {
        guard let data = defaults.data(forKey: defaultsKey),
              let store = try? JSONDecoder().decode(AppLaunchBindingStore.self, from: data) else {
            return AppLaunchBindingStore()
        }
        return store
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// 面板键位合并视图：功能绑定优先，其次应用绑定，未绑为空键位。
public enum HotkeyPanelContent {

    /// 单个键帽内容。
    public enum Cell: Equatable {
        /// 已绑功能：功能 id + 展示名 + SF Symbol 名。
        case function(id: String, title: String, symbolName: String)
        /// 已绑应用：bundleID + 应用名。
        case app(bundleID: String, name: String)
        /// 未绑：键位字符。
        case empty(keyLabel: String)
    }

    /// 功能 id → SF Symbol 名（键帽图标）。
    public static let symbolNames: [String: String] = [
        "screenshot": "camera.viewfinder",
        "transfer-shelf": "arrow.left.arrow.right",
        "screen-recording": "record.circle",
        "color-picker": "eyedropper",
        "portMonitor": "network",
        "clipboardHistory": "clipboard",
        "scratchpad": "square.and.pencil",
        "dictation": "mic.fill",
        "translate": "character.bubble",
        "gifRecorder": "animated",
        "launcher": "square.grid.2x2",
        "calendar": "calendar",
        "textToolkit": "textformat",
        "hotkeyPanel": "keyboard",
    ]

    public static func symbolName(for id: String) -> String? {
        symbolNames[id]
    }

    /// 键位字符 → 键帽内容（纯函数）：先查功能绑定（面板键帽无 shift 语义，
    /// 同键码即点亮），再查应用绑定，否则空键位。
    public static func cell(for keyChar: Character,
                            prefs: HotkeyPreferences,
                            appStore: AppLaunchBindingStore) -> Cell {
        let key = Character(keyChar.uppercased())
        guard let keyCode = HotkeyPanelKeyCodes.keyCode(for: key) else {
            return .empty(keyLabel: String(key))
        }
        // 功能绑定：按目录顺序查（同键码多绑时点亮目录首个，确定性可测）
        if let entry = HotkeyPreferences.catalog.first(where: { prefs.bindings[$0.id]?.keyCode == keyCode }) {
            return .function(id: entry.id, title: entry.title,
                             symbolName: symbolName(for: entry.id) ?? "square.grid.2x2")
        }
        if let app = appStore.binding(forKeyCode: keyCode) {
            return .app(bundleID: app.bundleID, name: app.name)
        }
        return .empty(keyLabel: String(key))
    }
}
