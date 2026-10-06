import XCTest

/// TDD: 取色历史 - 容量 5、连续重复项去重、超出容量丢最旧。
final class ColorHistoryTests: XCTestCase {

    func test_defaultCapacityIsFive() {
        XCTAssertEqual(ColorHistory().capacity, 5)
    }

    func test_capacityDropsOldest() {
        let history = ColorHistory()
        for hex in ["#111111", "#222222", "#333333", "#444444", "#555555", "#666666"] {
            history.record(hex)
        }
        XCTAssertEqual(history.entries, ["#222222", "#333333", "#444444", "#555555", "#666666"])
    }

    func test_consecutiveDuplicatesDeduped() {
        let history = ColorHistory()
        history.record("#AAAAAA")
        history.record("#AAAAAA")
        history.record("#AAAAAA")
        XCTAssertEqual(history.entries, ["#AAAAAA"])
    }

    func test_nonConsecutiveDuplicateKept() {
        let history = ColorHistory()
        history.record("#AAAAAA")
        history.record("#BBBBBB")
        history.record("#AAAAAA")
        XCTAssertEqual(history.entries, ["#AAAAAA", "#BBBBBB", "#AAAAAA"])
    }

    func test_emptyStringIgnored() {
        let history = ColorHistory()
        history.record("")
        XCTAssertTrue(history.entries.isEmpty)
    }

    func test_removeAll() {
        let history = ColorHistory()
        history.record("#AAAAAA")
        history.removeAll()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func test_customCapacity() {
        let history = ColorHistory(capacity: 2)
        history.record("#1")
        history.record("#2")
        history.record("#3")
        XCTAssertEqual(history.entries, ["#2", "#3"])
    }
}
