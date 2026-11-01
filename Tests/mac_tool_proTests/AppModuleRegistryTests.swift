import XCTest

/// TDD: App 级功能模块注册表 - 注册/查找/启用状态。
/// 热键注册已统一迁移到 HotkeyManager.applyPreferences（Alt 主键方案），
/// 注册表不再绑定热键；「启用过滤」由 AppDelegate 的 guarded handler 闭包承担，
/// 其行为在 HotkeyApplyHandlersTests 覆盖。
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

    func test_setEnabled_persistsAcrossInstances() {
        let suiteName = "AppModuleRegistryTests.persist"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let registry = AppModuleRegistry(
            hotkeyManager: HotkeyManager(registrar: FakeHotkeyRegistrar()),
            configDefaults: defaults)
        registry.register(FakeModule(id: "screenshot"))
        registry.setEnabled("screenshot", false)

        let reloaded = AppModuleRegistry(
            hotkeyManager: HotkeyManager(registrar: FakeHotkeyRegistrar()),
            configDefaults: defaults)
        reloaded.register(FakeModule(id: "screenshot"))
        XCTAssertFalse(reloaded.isEnabled("screenshot"), "启用状态必须持久化")
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeRegistry() -> AppModuleRegistry {
        let defaults = UserDefaults(suiteName: "AppModuleRegistryTests")!
        defaults.removePersistentDomain(forName: "AppModuleRegistryTests")
        return AppModuleRegistry(
            hotkeyManager: HotkeyManager(registrar: FakeHotkeyRegistrar()),
            configDefaults: defaults
        )
    }
}

final class FakeModule: AppModule {
    let id: String
    let title: String
    let defaultHotkey: Hotkey?
    var performCount = 0
    init(id: String, hotkey: Hotkey? = nil) {
        self.id = id
        self.title = id
        self.defaultHotkey = hotkey
    }
    func perform() { performCount += 1 }
}
