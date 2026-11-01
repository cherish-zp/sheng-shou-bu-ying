import Foundation

/// 快捷键「主键」体系（对标浮引 ctrl 主键 + 组合键）：全局唯一主修饰键
/// （默认 Option ⌥，可在设置切换 ⌃/⌘），每个功能只配组合键（字母键码 + 可选 shift）。
/// 改主键后所有功能热键一起变；卡片序号徽章随主键显示（⌥1、⌥2…）。
public enum PrimaryModifier: String, Codable, CaseIterable {
    case option
    case control
    case command

    public var carbonMask: UInt32 {
        switch self {
        case .option: return ModifierKey.option
        case .control: return ModifierKey.control
        case .command: return ModifierKey.command
        }
    }

    /// 菜单/徽章显示符号。
    public var symbol: String {
        switch self {
        case .option: return "⌥"
        case .control: return "⌃"
        case .command: return "⌘"
        }
    }

    /// 设置页显示名。
    public var displayName: String {
        switch self {
        case .option: return "Option ⌥"
        case .control: return "Control ⌃"
        case .command: return "Command ⌘"
        }
    }
}

/// 单个功能的组合键绑定：组合键键码 + 可选 shift 附加。
public struct HotkeyBinding: Codable, Equatable {
    public var keyCode: UInt32
    public var usesShift: Bool

    public init(keyCode: UInt32, usesShift: Bool = false) {
        self.keyCode = keyCode
        self.usesShift = usesShift
    }
}

/// 快捷键方案：主修饰键 + 各功能绑定 + 冲突检测。Codable 便于 UserDefaults 持久化。
public struct HotkeyPreferences: Codable, Equatable {

    public var primaryModifier: PrimaryModifier
    public var bindings: [String: HotkeyBinding]

    public init(primaryModifier: PrimaryModifier = .option,
                bindings: [String: HotkeyBinding]? = nil) {
        self.primaryModifier = primaryModifier
        self.bindings = bindings ?? HotkeyPreferences.defaultBindings()
    }

    /// 解析某功能的最终热键（主修饰键 [+ shift] + 组合键）；无绑定返回 nil。
    public func hotkey(for id: String) -> Hotkey? {
        guard let binding = bindings[id] else { return nil }
        var modifiers = primaryModifier.carbonMask
        if binding.usesShift { modifiers |= ModifierKey.shift }
        return Hotkey(keyCode: binding.keyCode, modifiers: modifiers)
    }

    /// 冲突检测：解析后热键完全相同的绑定分组（≥2 个才算冲突）。
    public func bindingConflictGroups() -> [[String]] {
        var byHotkey: [Hotkey: [String]] = [:]
        for (id, _) in bindings {
            guard let hotkey = hotkey(for: id) else { continue }
            byHotkey[hotkey, default: []].append(id)
        }
        return byHotkey.values.filter { $0.count > 1 }
    }

    /// 功能 i 的显示名（如 "⌥A"、"⌥⇧A"）；无绑定返回 nil。
    public func displayLabel(for id: String) -> String? {
        guard let binding = bindings[id] else { return nil }
        var label = primaryModifier.symbol
        if binding.usesShift { label += "⇧" }
        label += Hotkey.letterLabel(for: binding.keyCode) ?? "?"
        return label
    }

    // MARK: - 默认方案（13 个功能全迁移 Alt 体系）

    /// 功能目录：id + 设置页展示名 + 默认组合键键码。
    /// 键码对照 HIToolbox kVK_ANSI_*：A=0 S=1 D=2 G=5 X=7 C=8 R=15 T=17
    /// P=35 U=32 L=37 K=40 N=45。
    public static let catalog: [(id: String, title: String, keyCode: UInt32)] = [
        ("clipboardHistory", "剪贴板历史", 7),
        ("screenshot", "截图", 0),
        ("transfer-shelf", "文件中转", 1),
        ("screen-recording", "录屏", 15),
        ("color-picker", "取色器", 8),
        ("portMonitor", "端口占用", 35),
        ("scratchpad", "速记", 45),
        ("dictation", "语音听写", 2),
        ("translate", "翻译", 17),
        ("gifRecorder", "录 GIF", 5),
        ("launcher", "启动器", 37),
        ("calendar", "日历", 40),
        ("textToolkit", "文本工具", 32),
    ]

    public static func defaultBindings() -> [String: HotkeyBinding] {
        Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, HotkeyBinding(keyCode: $0.keyCode)) })
    }

    public static func withDefaults() -> HotkeyPreferences {
        HotkeyPreferences()
    }
}

// MARK: - UserDefaults 持久化

public extension HotkeyPreferences {
    static let defaultsKey = "hotkeyPreferences"

    /// 读取已保存方案；缺失/损坏时返回默认方案（13 绑定 ⌥ 系）。
    static func load() -> HotkeyPreferences {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let prefs = try? JSONDecoder().decode(HotkeyPreferences.self, from: data) else {
            return .withDefaults()
        }
        return prefs
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
