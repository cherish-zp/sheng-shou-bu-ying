import Foundation

/// 快捷键设置面板的可测纯逻辑：录制捕获规则 + 冲突/失败提示文案。
/// 录制语义 = 主修饰键（全局选择，不参与录制）+ 单键（⇧ 可叠加）。
public enum HotkeyCaptureResult: Equatable {
    case cancel               // Esc：取消录制
    case ignore               // 纯修饰键：忽略、继续等待
    case bind(HotkeyBinding)  // 有效组合键：候选绑定
}

public enum HotkeyCapture {

    /// Esc 键码（HIToolbox kVK_Escape）。
    public static let escapeKeyCode: UInt32 = 53

    /// 纯修饰键键码（HIToolbox kVK_*）：左右 Command(55/54)、Shift(56/60)、
    /// Option(58/61)、Control(59/62)、CapsLock(57)、Fn(63)。
    public static let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// keyDown 事件 → 录制结果（纯函数）：Esc 取消、纯修饰键忽略、
    /// 其他键取键码 + 是否按住 shift 作为候选绑定（其余修饰键不进入绑定）。
    public static func resolve(keyCode: UInt32, shiftHeld: Bool) -> HotkeyCaptureResult {
        if keyCode == escapeKeyCode { return .cancel }
        if modifierKeyCodes.contains(keyCode) { return .ignore }
        return .bind(HotkeyBinding(keyCode: keyCode, usesShift: shiftHeld))
    }
}

public enum HotkeySettingsLogic {

    /// 候选方案下 changingId 的冲突提示文案（冲突对手标题从目录查）；无冲突返回 nil。
    public static func conflictMessage(candidate: HotkeyPreferences,
                                       changingId: String,
                                       catalog: [(id: String, title: String, keyCode: UInt32)] = HotkeyPreferences.catalog) -> String? {
        guard let group = candidate.bindingConflictGroups().first(where: { $0.contains(changingId) }) else {
            return nil
        }
        let otherId = group.first { $0 != changingId } ?? changingId
        let title = catalog.first(where: { $0.id == otherId })?.title ?? otherId
        return "与「\(title)」冲突，未保存"
    }

    /// 注册失败警告条文案（列出失败功能名）；无失败返回 nil。
    public static func failureMessage(failures: [String: Hotkey],
                                      catalog: [(id: String, title: String, keyCode: UInt32)] = HotkeyPreferences.catalog) -> String? {
        guard !failures.isEmpty else { return nil }
        let names = failures.keys
            .map { id in catalog.first(where: { $0.id == id })?.title ?? id }
            .sorted()
            .joined(separator: "、")
        return "\(failures.count) 个快捷键注册失败，可能被其他应用占用：\(names)"
    }
}
