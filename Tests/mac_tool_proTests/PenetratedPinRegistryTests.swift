import XCTest

/// TDD: 贴图穿透登记表 - 登记/移除/计数/清空取出；弱引用不延长贴图生命周期。
final class PenetratedPinRegistryTests: XCTestCase {

    private final class DummyPin {}

    func test_addIncrementsCount() {
        let registry = PenetratedPinRegistry()
        let pin = DummyPin()
        registry.add(pin)
        XCTAssertEqual(registry.count, 1)
    }

    func test_removeDecrementsCount() {
        let registry = PenetratedPinRegistry()
        let pin = DummyPin()
        registry.add(pin)
        registry.remove(pin)
        XCTAssertEqual(registry.count, 0)
    }

    func test_allEntriesReturnsAddedObjects() {
        let registry = PenetratedPinRegistry()
        let a = DummyPin(), b = DummyPin()
        registry.add(a)
        registry.add(b)
        XCTAssertEqual(registry.allEntries.count, 2)
        XCTAssertTrue(registry.allEntries.contains { $0 === a })
        XCTAssertTrue(registry.allEntries.contains { $0 === b })
    }

    func test_removeAllEntriesDrainsAndReturns() {
        let registry = PenetratedPinRegistry()
        let a = DummyPin(), b = DummyPin()
        registry.add(a)
        registry.add(b)
        let drained = registry.removeAllEntries()
        XCTAssertEqual(drained.count, 2)
        XCTAssertEqual(registry.count, 0, "取出后清空")
    }

    func test_sharedInstanceIsSingleton() {
        XCTAssertTrue(PenetratedPinRegistry.shared === PenetratedPinRegistry.shared)
    }

    func test_duplicateAddCountsOnce() {
        let registry = PenetratedPinRegistry()
        let pin = DummyPin()
        registry.add(pin)
        registry.add(pin)
        XCTAssertEqual(registry.count, 1, "NSHashTable 语义：同对象重复登记只算一次")
    }
}
