import XCTest

/// TDD: 剪贴板历史存储 —— 去重、置顶收藏、容量淘汰（收藏豁免）。
final class ClipboardHistoryStoreTests: XCTestCase {

    private func item(_ text: String, favorite: Bool = false, at: Date = Date()) -> ClipboardHistoryItem {
        ClipboardHistoryItem(kind: .text, text: text, addedAt: at, isFavorite: favorite)
    }

    func test_add_dedupsConsecutiveDuplicate() {
        var store = ClipboardHistoryStore()
        store.add(item("a"))
        store.add(item("a"))
        XCTAssertEqual(store.items.count, 1, "连续相同内容忽略")
    }

    func test_add_movesExistingToFront() {
        var store = ClipboardHistoryStore()
        store.add(item("a"))
        store.add(item("b"))
        store.add(item("a"))
        XCTAssertEqual(store.items.map(\.text), ["a", "b"], "再次复制旧内容应提到最前")
    }

    func test_favorite_pinnedToTop() {
        var store = ClipboardHistoryStore()
        store.add(item("a"))
        store.add(item("b"))
        store.add(item("c"))
        store.toggleFavorite(id: store.items.first(where: { $0.text == "a" })!.id)
        XCTAssertEqual(store.displayOrder.map(\.text), ["a", "c", "b"], "收藏置顶")
    }

    func test_capacity_evictsOldestUnfavoriteFirst() {
        var store = ClipboardHistoryStore(capacity: 2)
        store.add(item("a", favorite: true))
        store.add(item("b"))
        store.add(item("c"))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.map(\.text), ["c", "a"], "收藏豁免淘汰，最旧的普通条目先走")
    }

    func test_roundtripCodable() throws {
        var store = ClipboardHistoryStore()
        store.add(item("persist"))
        store.toggleFavorite(id: store.items[0].id)
        let data = try JSONEncoder().encode(store)
        let back = try JSONDecoder().decode(ClipboardHistoryStore.self, from: data)
        XCTAssertEqual(back, store)
    }
}
