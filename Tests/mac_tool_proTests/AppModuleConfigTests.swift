import XCTest

/// TDD: App 模块启用状态应跨 registry 实例持久化。
final class AppModuleConfigTests: XCTestCase {

    func test_disableModule_persistsAcrossRegistries() {
        let defaults = UserDefaults(suiteName: "AppModuleConfigTests")!
        defaults.removePersistentDomain(forName: "AppModuleConfigTests")
        let firstHotkeyManager = HotkeyManager(registrar: FakeHotkeyRegistrar())
        let firstRegistry = AppModuleRegistry(
            hotkeyManager: firstHotkeyManager,
            configDefaults: defaults
        )

        firstRegistry.setEnabled("screenshot", false)

        let secondHotkeyManager = HotkeyManager(registrar: FakeHotkeyRegistrar())
        let secondRegistry = AppModuleRegistry(
            hotkeyManager: secondHotkeyManager,
            configDefaults: defaults
        )
        secondRegistry.register(FakeModule(id: "screenshot"))

        XCTAssertFalse(secondRegistry.isEnabled("screenshot"))
    }
}
