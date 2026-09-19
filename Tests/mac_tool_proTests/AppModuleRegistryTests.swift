import XCTest

/// TDD: App 级功能模块注册表 - 注册/查找/启用状态/把启用模块绑定到热键。
final class AppModuleRegistryTests: XCTestCase {

    func test_register_andFind() {
        let registry = makeRegistry()
        let module = FakeModule(id: "screenshot")
        registry.register(module)
        XCTAssertIdentical(registry.module(for: "screenshot"), module)
        XCTAssertNil(registry.module(for: "nope"))
    }

    func test_enabledByDefault() {
        let registry = makeRegistry()
        XCTAssertTrue(registry.isEnabled("screenshot"))
    }

    func test_enabledModule_hotkeyTriggersPerform() {
        let registrar = FakeHotkeyRegistrar()
        let registry = makeRegistry(hotkeyManager: HotkeyManager(registrar: registrar))
        let module = FakeModule(id: "screenshot", hotkey: .f1)
        registry.register(module)

        let id = registrar.registered.first(where: { $0.value == module.defaultHotkey })?.key
        XCTAssertNotNil(id, "启用模块应已注册热键")
        registrar.onTrigger?(id!)
        XCTAssertEqual(module.performCount, 1)
    }

    func test_disableModule_unregistersHotkey() {
        let registrar = FakeHotkeyRegistrar()
        let registry = makeRegistry(hotkeyManager: HotkeyManager(registrar: registrar))
        let module = FakeModule(id: "screenshot", hotkey: .f1)
        registry.register(module)
        registry.setEnabled("screenshot", false)

        XCTAssertNil(registrar.registered.first(where: { $0.value == module.defaultHotkey }))
        XCTAssertTrue(registrar.registered.isEmpty)
    }

    func test_reEnable_rebindsHotkey() {
        let registrar = FakeHotkeyRegistrar()
        let registry = makeRegistry(hotkeyManager: HotkeyManager(registrar: registrar))
        let module = FakeModule(id: "screenshot", hotkey: .f1)
        registry.register(module)
        registry.setEnabled("screenshot", false)
        registry.setEnabled("screenshot", true)

        let id = registrar.registered.first(where: { $0.value == module.defaultHotkey })?.key
        XCTAssertNotNil(id)
        registrar.onTrigger?(id!)
        XCTAssertEqual(module.performCount, 1)
    }

    private func makeRegistry(hotkeyManager: HotkeyManager? = nil) -> AppModuleRegistry {
        let defaults = UserDefaults(suiteName: "AppModuleRegistryTests")!
        defaults.removePersistentDomain(forName: "AppModuleRegistryTests")
        return AppModuleRegistry(
            hotkeyManager: hotkeyManager ?? HotkeyManager(registrar: FakeHotkeyRegistrar()),
            configDefaults: defaults
        )
    }
}

final class FakeModule: AppModule {
    let id: String
    let title: String
    let defaultHotkey: Hotkey
    var performCount = 0
    init(id: String, hotkey: Hotkey = .f1) {
        self.id = id
        self.title = id
        self.defaultHotkey = hotkey
    }
    func perform() { performCount += 1 }
}
