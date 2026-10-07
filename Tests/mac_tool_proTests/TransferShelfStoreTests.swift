import XCTest
import Foundation

/// TDD: 文件中转站存储 - URL 引用式暂存，不复制文件本体。
final class TransferShelfStoreTests: XCTestCase {

    func test_addStoresURLReference() {
        var store = TransferShelfStore()
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        let item = store.add(url: url)
        XCTAssertEqual(item?.url, url)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.name, "report.pdf")
    }

    func test_addDuplicateURLIsIgnored() {
        var store = TransferShelfStore()
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        XCTAssertNotNil(store.add(url: url))
        XCTAssertNil(store.add(url: url))
        XCTAssertEqual(store.items.count, 1)
    }

    func test_removeByID() {
        var store = TransferShelfStore()
        let item = store.add(url: URL(fileURLWithPath: "/tmp/a.txt"))!
        XCTAssertTrue(store.remove(id: item.id))
        XCTAssertFalse(store.remove(id: item.id))
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_persistenceRoundtrip() throws {
        var store = TransferShelfStore()
        store.add(url: URL(fileURLWithPath: "/tmp/a.txt"))
        store.add(url: URL(fileURLWithPath: "/tmp/b.txt"))
        let data = try XCTUnwrap(store.encode())
        let restored = try XCTUnwrap(TransferShelfStore.load(from: data))
        XCTAssertEqual(restored.items.map(\.url.path), ["/tmp/a.txt", "/tmp/b.txt"])
    }

    // MARK: - 损坏数据显式区分（不再无声清空）

    func test_loadInvalidDataReturnsNil() {
        let data = Data("not-json{{".utf8)
        XCTAssertNil(TransferShelfStore.load(from: data), "解码失败必须显式返回 nil，交由调用方备份损坏文件")
    }

    func test_loadValidJSONButWrongShapeReturnsNil() throws {
        let data = try XCTUnwrap(#"{"foo": 1}"#.data(using: .utf8))
        XCTAssertNil(TransferShelfStore.load(from: data))
    }

    // MARK: - 条目上限（超限淘汰最旧）

    func test_addEvictsOldestWhenExceedingMaxCount() {
        var store = TransferShelfStore(maxCount: 2)
        store.add(url: URL(fileURLWithPath: "/tmp/1.txt"))
        store.add(url: URL(fileURLWithPath: "/tmp/2.txt"))
        store.add(url: URL(fileURLWithPath: "/tmp/3.txt"))
        XCTAssertEqual(store.items.map(\.url.path), ["/tmp/2.txt", "/tmp/3.txt"],
                       "超限时应淘汰最旧的条目")
    }

    func test_defaultMaxCountIs20() {
        var store = TransferShelfStore()
        XCTAssertEqual(store.maxCount, 20)
        for i in 0..<25 {
            store.add(url: URL(fileURLWithPath: "/tmp/item\(i).txt"))
        }
        XCTAssertEqual(store.items.count, 20)
        XCTAssertEqual(store.items.first?.url.path, "/tmp/item5.txt", "最旧的 5 条应被淘汰")
        XCTAssertEqual(store.items.last?.url.path, "/tmp/item24.txt")
    }

    func test_addDuplicateAtCapacityDoesNotEvict() {
        var store = TransferShelfStore(maxCount: 2)
        store.add(url: URL(fileURLWithPath: "/tmp/1.txt"))
        store.add(url: URL(fileURLWithPath: "/tmp/2.txt"))
        XCTAssertNil(store.add(url: URL(fileURLWithPath: "/tmp/2.txt")), "去重命中不应触发淘汰")
        XCTAssertEqual(store.items.map(\.url.path), ["/tmp/1.txt", "/tmp/2.txt"])
    }

    func test_loadTrimsToMaxCount_keepingNewest() throws {
        var store = TransferShelfStore()
        for i in 0..<5 {
            store.add(url: URL(fileURLWithPath: "/tmp/item\(i).txt"))
        }
        let data = try XCTUnwrap(store.encode())
        let restored = try XCTUnwrap(TransferShelfStore.load(from: data, maxCount: 3))
        XCTAssertEqual(restored.items.map(\.url.path),
                       ["/tmp/item2.txt", "/tmp/item3.txt", "/tmp/item4.txt"],
                       "历史遗留的超长列表应裁剪到上限内（保留最新）")
    }

    func test_clearRemovesAllItems() {
        var store = TransferShelfStore()
        store.add(url: URL(fileURLWithPath: "/tmp/a.txt"))
        store.add(url: URL(fileURLWithPath: "/tmp/b.txt"))
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_clearOnEmptyStoreIsSafe() {
        var store = TransferShelfStore()
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_expiredItemWhenFileMissing() {
        let store = TransferShelfStore()
        let item = TransferItem(id: UUID(), url: URL(fileURLWithPath: "/gone.txt"),
                                name: "gone.txt", addedAt: Date())
        XCTAssertFalse(store.isValid(item, fileExists: { _ in false }))
        XCTAssertTrue(store.isValid(item, fileExists: { _ in true }))
    }

    // MARK: - 失效自动清理（文件被移走/删除后应从中转站移除）

    func test_purgeInvalid_removesOnlyMissingItems_andKeepsOrder() {
        var store = TransferShelfStore()
        store.add(url: URL(fileURLWithPath: "/tmp/a.txt"))
        store.add(url: URL(fileURLWithPath: "/tmp/gone.txt"))
        store.add(url: URL(fileURLWithPath: "/tmp/b.txt"))
        store.add(url: URL(fileURLWithPath: "/tmp/also-gone.txt"))

        let existing: Set<String> = ["/tmp/a.txt", "/tmp/b.txt"]
        let removed = store.purgeInvalid(fileExists: { existing.contains($0.path) })

        XCTAssertEqual(store.items.map(\.url.path), ["/tmp/a.txt", "/tmp/b.txt"],
                       "只应保留文件仍存在的条目，且保持原有顺序")
        XCTAssertEqual(removed.map(\.url.path), ["/tmp/gone.txt", "/tmp/also-gone.txt"],
                       "应返回被移除的失效条目")
    }

    func test_purgeInvalid_allValid_removesNothing() {
        var store = TransferShelfStore()
        store.add(url: URL(fileURLWithPath: "/tmp/a.txt"))
        let removed = store.purgeInvalid(fileExists: { _ in true })
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(store.items.count, 1)
    }

    func test_purgeInvalid_onEmptyStoreIsSafe() {
        var store = TransferShelfStore()
        let removed = store.purgeInvalid(fileExists: { _ in false })
        XCTAssertTrue(removed.isEmpty)
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_purgeInvalid_removesAllWhenAllMissing() {
        var store = TransferShelfStore()
        store.add(url: URL(fileURLWithPath: "/tmp/gone1.txt"))
        store.add(url: URL(fileURLWithPath: "/tmp/gone2.txt"))
        let removed = store.purgeInvalid(fileExists: { _ in false })
        XCTAssertEqual(removed.count, 2)
        XCTAssertTrue(store.items.isEmpty)
    }
}
