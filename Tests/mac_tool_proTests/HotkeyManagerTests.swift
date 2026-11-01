import XCTest

/// TDD: 热键管理器 - 注册/注销/分发，注入 HotkeyRegistrar 便于测试。
final class HotkeyManagerTests: XCTestCase {

    func test_register_dispatchesHandler() {
        let registrar = FakeHotkeyRegistrar()
        let manager = HotkeyManager(registrar: registrar)
        var fired = false
        let id = manager.register(Hotkey.f1) { fired = true }
        XCTAssertNotNil(id)
        registrar.onTrigger?(id!)   // 模拟 F1 按下
        XCTAssertTrue(fired)
    }

    func test_register_sameHotkey_conflict_returnsNil() {
        let manager = HotkeyManager(registrar: FakeHotkeyRegistrar())
        XCTAssertNotNil(manager.register(Hotkey.f1) {})
        XCTAssertNil(manager.register(Hotkey.f1) {})
    }

    func test_unregister_removesHandler() {
        let registrar = FakeHotkeyRegistrar()
        let manager = HotkeyManager(registrar: registrar)
        var fired = false
        let id = manager.register(Hotkey.f1) { fired = true }
        manager.unregister(Hotkey.f1)
        registrar.onTrigger?(id!)
        XCTAssertFalse(fired)
    }

    func test_differentHotkeys_dispatchIndependently() {
        let registrar = FakeHotkeyRegistrar()
        let manager = HotkeyManager(registrar: registrar)
        var a = 0, b = 0
        let idA = manager.register(Hotkey.f1) { a += 1 }
        let idB = manager.register(Hotkey(keyCode: 45, modifiers: ModifierKey.command)) { b += 1 }
        registrar.onTrigger?(idA!)
        registrar.onTrigger?(idB!)
        XCTAssertEqual(a, 1)
        XCTAssertEqual(b, 1)
    }

    func test_registerFailure_returnsNil() {
        let manager = HotkeyManager(registrar: FailingRegistrar())
        XCTAssertNil(manager.register(Hotkey.f1) {})
    }
}

final class FakeHotkeyRegistrar: HotkeyRegistrar {
    var onTrigger: ((UInt32) -> Void)?
    var registered: [UInt32: Hotkey] = [:]
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        registered[id] = Hotkey(keyCode: keyCode, modifiers: modifiers)
        return true
    }
    func unregister(id: UInt32) { registered.removeValue(forKey: id) }
}

final class FailingRegistrar: HotkeyRegistrar {
    var onTrigger: ((UInt32) -> Void)?
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool { false }
    func unregister(id: UInt32) {}
}

// MARK: - applyPreferences（Alt 主键方案应用）

extension HotkeyManagerTests {

    func test_applyPreferences_unregistersOldAndRegistersPlan() {
        let registrar = FakeHotkeyRegistrar()
        let manager = HotkeyManager(registrar: registrar)
        var firedOld = false, firedNew = false
        manager.register(Hotkey.f1) { firedOld = true }   // 旧 F1 注册
        let prefs = HotkeyPreferences.withDefaults()
        let failures = manager.applyPreferences(prefs, handlers: ["screenshot": { firedNew = true }])

        XCTAssertTrue(failures.isEmpty)
        XCTAssertTrue(firedNew == false)
        // 旧 F1 已全部注销：fake registrar 里不应再有 F1
        XCTAssertFalse(registrar.registered.values.contains(Hotkey.f1))
        // 新方案已注册 ⌥A
        XCTAssertTrue(registrar.registered.values.contains(
            Hotkey(keyCode: 0, modifiers: ModifierKey.option)))
        _ = firedOld
    }

    func test_applyPreferences_conflictingBindingsAreSkippedAndReported() {
        let registrar = FakeHotkeyRegistrar()
        let manager = HotkeyManager(registrar: registrar)
        var prefs = HotkeyPreferences.withDefaults()
        prefs.bindings["screenshot"] = HotkeyBinding(keyCode: 7)   // 与剪贴板冲突
        var fired = false
        let failures = manager.applyPreferences(prefs, handlers: [
            "screenshot": { fired = true },
            "clipboardHistory": {},
        ])
        // 冲突双方都不注册，且都在失败表里
        XCTAssertEqual(Set(failures.keys), ["screenshot", "clipboardHistory"])
        XCTAssertFalse(registrar.registered.values.contains(
            Hotkey(keyCode: 7, modifiers: ModifierKey.option)))
        _ = fired
    }

    func test_applyPreferences_reportsSystemRegistrationFailure() {
        let manager = HotkeyManager(registrar: FailingRegistrar())
        let prefs = HotkeyPreferences.withDefaults()
        let failures = manager.applyPreferences(prefs, handlers: ["screenshot": {}])
        XCTAssertEqual(failures["screenshot"], Hotkey(keyCode: 0, modifiers: ModifierKey.option),
                       "系统注册失败要进失败表（UI 提示用）")
    }

    func test_applyPreferences_bindingWithoutHandlerIsSkipped() {
        let registrar = FakeHotkeyRegistrar()
        let manager = HotkeyManager(registrar: registrar)
        let prefs = HotkeyPreferences.withDefaults()
        let failures = manager.applyPreferences(prefs, handlers: ["screenshot": {}])
        XCTAssertTrue(failures.isEmpty)
        XCTAssertGreaterThan(registrar.registered.count, 0)
        XCTAssertLessThanOrEqual(registrar.registered.count, 1, "无 handler 的绑定不注册")
    }
}
