import XCTest

/// TDD: 贴图 App 级持有者 —— 贴图常驻桌面的生命周期必须独立于单次截图会话的协调器
/// （协调器每次 F1 重建，旧实例释放曾连带释放全部在屏贴图）。
final class PinStoreTests: XCTestCase {

    func test_add_and_remove_byIdentity() {
        // PinWindow 为 AppKit 窗口：用占位对象验证按身份移除语义
        final class FakePin: NSObject {}
        let store = PinStore<FakePin>()

        let a = FakePin(), b = FakePin()
        store.add(a)
        store.add(b)
        XCTAssertFalse(store.isEmpty)

        store.remove(a)
        XCTAssertTrue(store.pins.contains(where: { $0 === b }))
        XCTAssertFalse(store.pins.contains(where: { $0 === a }))

        store.remove(b)
        XCTAssertTrue(store.isEmpty)
    }

    func test_remove_unknown_isNoop() {
        final class FakePin: NSObject {}
        let store = PinStore<FakePin>()
        let a = FakePin()
        store.add(a)
        store.remove(FakePin())
        XCTAssertEqual(store.pins.count, 1)
    }
}
