import XCTest
import CoreGraphics

/// TDD: 上次截图区域记录 - UserDefaults 持久化 round-trip、clear、损坏数据容错。
final class LastRegionStoreTests: XCTestCase {

    private func makeIsolatedStore() -> (LastRegionStore, UserDefaults) {
        let suite = "LastRegionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (LastRegionStore(defaults: defaults), defaults)
    }

    func test_load_returnsNilWhenEmpty() {
        let (store, _) = makeIsolatedStore()
        XCTAssertNil(store.load())
    }

    func test_saveLoad_roundTrip() {
        let (store, _) = makeIsolatedStore()
        let record = LastRegionRecord(rect: CGRect(x: 10, y: 20, width: 300, height: 200),
                                      displayID: 5, screenPointSize: CGSize(width: 1512, height: 982))
        store.save(record)
        XCTAssertEqual(store.load(), record)
    }

    func test_clear_removesRecord() {
        let (store, _) = makeIsolatedStore()
        store.save(LastRegionRecord(rect: .zero, displayID: 1, screenPointSize: CGSize(width: 100, height: 100)))
        store.clear()
        XCTAssertNil(store.load())
    }

    func test_corruptedData_returnsNil() {
        let (store, defaults) = makeIsolatedStore()
        defaults.set(Data("not-json".utf8), forKey: LastRegionStore.defaultsKey)
        XCTAssertNil(store.load(), "损坏数据容错返回 nil")
    }
}
