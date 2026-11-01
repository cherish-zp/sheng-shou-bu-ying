import XCTest

/// TDD: Alt 主键快捷键体系 —— 主修饰键 + 每功能组合键 + 冲突检测 + 默认 13 绑定。
/// 对标浮引（ctrl 主键 + 组合键）；本 app 默认主键 Option ⌥。
final class HotkeyPlanTests: XCTestCase {

    // MARK: - 主修饰键

    func test_primaryModifier_masksMatchCarbon() {
        XCTAssertEqual(PrimaryModifier.option.carbonMask, ModifierKey.option)
        XCTAssertEqual(PrimaryModifier.control.carbonMask, ModifierKey.control)
        XCTAssertEqual(PrimaryModifier.command.carbonMask, ModifierKey.command)
    }

    func test_primaryModifier_defaultIsOption() {
        XCTAssertEqual(HotkeyPreferences.withDefaults().primaryModifier, .option,
                       "默认主键 = Option（Alt）")
    }

    // MARK: - 解析热键

    func test_resolvedHotkey_combinesPrimaryAndShift() {
        var prefs = HotkeyPreferences.withDefaults()
        prefs.bindings["screenshot"] = HotkeyBinding(keyCode: 0, usesShift: true)
        let hotkey = prefs.hotkey(for: "screenshot")
        XCTAssertEqual(hotkey?.keyCode, 0)
        XCTAssertEqual(hotkey?.modifiers, ModifierKey.option | ModifierKey.shift,
                       "⌥⇧A：主修饰键 + shift")
    }

    func test_resolvedHotkey_missingBindingReturnsNil() {
        var prefs = HotkeyPreferences.withDefaults()
        prefs.bindings["screenshot"] = nil
        XCTAssertNil(prefs.hotkey(for: "screenshot"))
    }

    // MARK: - 默认绑定（13 个功能全迁移 Alt 体系）

    func test_defaults_thirteenBindings_noConflicts() {
        let prefs = HotkeyPreferences.withDefaults()
        XCTAssertEqual(prefs.bindings.count, 13)
        XCTAssertTrue(prefs.bindingConflictGroups().isEmpty, "默认绑定不得自相冲突")
    }

    func test_defaults_expectedAssignment() {
        let prefs = HotkeyPreferences.withDefaults()
        // ⌥X 剪贴板 / ⌥A 截图 / ⌥S 中转 / ⌥R 录屏 / ⌥C 取色 / ⌥P 端口
        XCTAssertEqual(prefs.bindings["clipboardHistory"]?.keyCode, 7)
        XCTAssertEqual(prefs.bindings["screenshot"]?.keyCode, 0)
        XCTAssertEqual(prefs.bindings["transfer-shelf"]?.keyCode, 1)
        XCTAssertEqual(prefs.bindings["screen-recording"]?.keyCode, 15)
        XCTAssertEqual(prefs.bindings["color-picker"]?.keyCode, 8)
        XCTAssertEqual(prefs.bindings["portMonitor"]?.keyCode, 35)
        // ⌥N 速记 / ⌥D 听写 / ⌥T 翻译 / ⌥G GIF / ⌥L 启动器 / ⌥K 日历 / ⌥U 文本工具
        XCTAssertEqual(prefs.bindings["scratchpad"]?.keyCode, 45)
        XCTAssertEqual(prefs.bindings["dictation"]?.keyCode, 2)
        XCTAssertEqual(prefs.bindings["translate"]?.keyCode, 17)
        XCTAssertEqual(prefs.bindings["gifRecorder"]?.keyCode, 5)
        XCTAssertEqual(prefs.bindings["launcher"]?.keyCode, 37)
        XCTAssertEqual(prefs.bindings["calendar"]?.keyCode, 40)
        XCTAssertEqual(prefs.bindings["textToolkit"]?.keyCode, 32)
    }

    // MARK: - 冲突检测

    func test_conflictDetection_sameKeyConflicts() {
        var prefs = HotkeyPreferences.withDefaults()
        prefs.bindings["screenshot"] = HotkeyBinding(keyCode: 7)   // 与剪贴板同键
        let groups = prefs.bindingConflictGroups()
        XCTAssertEqual(groups.count, 1, "只有一组冲突")
        XCTAssertEqual(Set(groups[0]), ["clipboardHistory", "screenshot"])
    }

    // MARK: - 显示名

    func test_displayLabel_primaryOnly() {
        let prefs = HotkeyPreferences.withDefaults()
        XCTAssertEqual(prefs.displayLabel(for: "screenshot"), "⌥A")
        XCTAssertEqual(prefs.displayLabel(for: "clipboardHistory"), "⌥X")
    }

    func test_displayLabel_withShift() {
        var prefs = HotkeyPreferences.withDefaults()
        prefs.bindings["screenshot"] = HotkeyBinding(keyCode: 0, usesShift: true)
        XCTAssertEqual(prefs.displayLabel(for: "screenshot"), "⌥⇧A")
    }

    func test_displayLabel_changesWithPrimary() {
        var prefs = HotkeyPreferences.withDefaults()
        prefs.primaryModifier = .control
        XCTAssertEqual(prefs.displayLabel(for: "screenshot"), "⌃A")
    }

    func test_letterLabel_commonKeys() {
        XCTAssertEqual(Hotkey.letterLabel(for: 0), "A")
        XCTAssertEqual(Hotkey.letterLabel(for: 7), "X")
        XCTAssertEqual(Hotkey.letterLabel(for: 11), "B")
        XCTAssertNil(Hotkey.letterLabel(for: 122), "功能键无字母名")
    }

    // MARK: - Codable 往返（UserDefaults 持久化）

    func test_codable_roundTrip() throws {
        let prefs = HotkeyPreferences.withDefaults()
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(HotkeyPreferences.self, from: data)
        XCTAssertEqual(decoded, prefs)
    }
}
