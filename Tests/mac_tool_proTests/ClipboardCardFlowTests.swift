import XCTest

/// TDD: 剪贴板卡片流面板的纯逻辑 —— 删除条目、卡片过滤、数字键码、相对时间。
final class ClipboardCardFlowTests: XCTestCase {

    // MARK: - ClipboardHistoryStore.remove(id:)

    private func item(_ text: String, kind: ClipboardHistoryItem.Kind = .text,
                      favorite: Bool = false) -> ClipboardHistoryItem {
        ClipboardHistoryItem(kind: kind, text: text, addedAt: Date(), isFavorite: favorite)
    }

    func test_store_remove_deletesExistingItem() {
        var store = ClipboardHistoryStore()
        store.add(item("a"))
        store.add(item("b"))
        let target = store.items.first(where: { $0.text == "b" })!
        store.remove(id: target.id)
        XCTAssertEqual(store.items.count, 1, "删除后少一条")
        XCTAssertFalse(store.items.contains { $0.id == target.id })
        XCTAssertEqual(store.items.map(\.text), ["a"])
    }

    func test_store_remove_ignoresUnknownID() {
        var store = ClipboardHistoryStore()
        store.add(item("a"))
        store.remove(id: UUID())
        XCTAssertEqual(store.items.count, 1, "删除不存在的 id 无变化")
        XCTAssertEqual(store.items.map(\.text), ["a"])
    }

    func test_store_remove_updatesDisplayOrder() {
        var store = ClipboardHistoryStore()
        store.add(item("a"))
        store.add(item("b", favorite: true))
        let favorite = store.items.first(where: { $0.text == "b" })!
        store.remove(id: favorite.id)
        XCTAssertEqual(store.displayOrder.map(\.text), ["a"], "删掉收藏条目后置顶位让出")
    }

    // MARK: - ClipboardCardFilter

    private func textItem(_ text: String) -> ClipboardHistoryItem {
        ClipboardHistoryItem(kind: .text, text: text)
    }

    private func fileItem(_ names: [String]) -> ClipboardHistoryItem {
        ClipboardHistoryItem(kind: .files, text: names.joined(separator: ", "),
                             filePaths: names.map { "/tmp/\($0)" })
    }

    func test_filter_nilKind_returnsAllInOrder() {
        let items = [textItem("hello"), fileItem(["a.txt"]),
                     ClipboardHistoryItem(kind: .image, text: "图片 100×80")]
        let result = ClipboardCardFilter.filter(items: items, searchText: "", kind: nil)
        XCTAssertEqual(result.map(\.text), ["hello", "a.txt", "图片 100×80"], "kind 为空=全部,保持原序")
    }

    func test_filter_searchMatchesTextContent_caseInsensitive() {
        let items = [textItem("Hello World"), textItem("swift code")]
        let result = ClipboardCardFilter.filter(items: items, searchText: "hello", kind: nil)
        XCTAssertEqual(result.map(\.text), ["Hello World"], "文本搜索大小写不敏感")
    }

    func test_filter_searchMatchesFileName() {
        let items = [fileItem(["报告.pdf", "photo.png"]), textItem("无关文本")]
        let result = ClipboardCardFilter.filter(items: items, searchText: "报告", kind: nil)
        XCTAssertEqual(result.count, 1, "文件条目按文件名匹配")
        XCTAssertEqual(result.first?.kind, .files)
    }

    func test_filter_kindNarrowsToTextOnly() {
        let items = [textItem("hello"), fileItem(["a.txt"]),
                     ClipboardHistoryItem(kind: .image, text: "图片 100×80")]
        let result = ClipboardCardFilter.filter(items: items, searchText: "", kind: .text)
        XCTAssertEqual(result.map(\.text), ["hello"])
    }

    func test_filter_combinesSearchAndKind() {
        let items = [textItem("apple pie"), textItem("banana"),
                     fileItem(["apple.txt"])]
        let result = ClipboardCardFilter.filter(items: items, searchText: "apple", kind: .files)
        XCTAssertEqual(result.count, 1, "kind + 搜索组合过滤")
        XCTAssertEqual(result.first?.kind, .files)
    }

    func test_filter_blankSearchReturnsAll() {
        let items = [textItem("hello"), textItem("world")]
        let result = ClipboardCardFilter.filter(items: items, searchText: "   ", kind: nil)
        XCTAssertEqual(result.count, 2, "纯空白搜索视为不过滤")
    }

    // MARK: - ClipboardDigitKeyCodes

    func test_digitKeyCodes_matchHIToolbox() {
        XCTAssertEqual(ClipboardDigitKeyCodes.keyCodes[1], 18)
        XCTAssertEqual(ClipboardDigitKeyCodes.keyCodes[2], 19)
        XCTAssertEqual(ClipboardDigitKeyCodes.keyCodes[3], 20)
        XCTAssertEqual(ClipboardDigitKeyCodes.keyCodes[4], 21)
        XCTAssertEqual(ClipboardDigitKeyCodes.keyCodes[5], 23)
        XCTAssertEqual(ClipboardDigitKeyCodes.keyCodes[6], 22)
        XCTAssertEqual(ClipboardDigitKeyCodes.keyCodes[7], 26)
        XCTAssertEqual(ClipboardDigitKeyCodes.keyCodes[8], 28)
        XCTAssertEqual(ClipboardDigitKeyCodes.keyCodes[9], 25)
        XCTAssertEqual(ClipboardDigitKeyCodes.keyCodes[0], 29)
    }

    func test_digitKeyCodes_label() {
        XCTAssertEqual(ClipboardDigitKeyCodes.label(for: 1), "1")
        XCTAssertEqual(ClipboardDigitKeyCodes.label(for: 9), "9")
        XCTAssertNil(ClipboardDigitKeyCodes.label(for: 10), "超出 1~9 无徽章文本")
    }

    // MARK: - RelativeTimeFormatter

    /// 固定基准时刻(GMT),防宿主时区影响。
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func test_relativeTime_justNow() {
        let label = RelativeTimeFormatter.label(from: base, to: base.addingTimeInterval(30),
                                                timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(label, "刚刚")
    }

    func test_relativeTime_minutesAgo() {
        let label = RelativeTimeFormatter.label(from: base, to: base.addingTimeInterval(120),
                                                timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(label, "2 分钟前")
    }

    func test_relativeTime_hoursAgo() {
        let label = RelativeTimeFormatter.label(from: base, to: base.addingTimeInterval(3 * 3600),
                                                timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(label, "3 小时前")
    }

    func test_relativeTime_daysAgo() {
        let label = RelativeTimeFormatter.label(from: base, to: base.addingTimeInterval(5 * 86400),
                                                timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(label, "5 天前")
    }

    func test_relativeTime_dateFallback() {
        // base = 2023-11-14 22:13:20 GMT;+400 天 = 2024-12-18
        let label = RelativeTimeFormatter.label(from: base, to: base.addingTimeInterval(400 * 86400),
                                                timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(label, "2024-12-18", "超过一周回落到日期显示(注入时区 GMT)")
    }

    func test_relativeTime_futureClampsToNow() {
        let label = RelativeTimeFormatter.label(from: base, to: base.addingTimeInterval(-60),
                                                timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(label, "刚刚", "未来时间(时钟回拨)按刚刚处理")
    }
}
