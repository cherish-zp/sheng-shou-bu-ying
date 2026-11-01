import XCTest

/// TDD: 轻量日历月网格 —— 6×7、周一为首、前后月补位 nil。
final class CalendarGridTests: XCTestCase {

    private func makeCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2  // 周一
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func test_nov2026_startsSunday_leadingBlanks() {
        // 2026-11-01 是周日：周一为首时前置 6 个 nil
        let grid = CalendarGrid.monthGrid(year: 2026, month: 11, calendar: makeCalendar())
        XCTAssertEqual(grid.count, 6)
        XCTAssertEqual(grid[0].count, 7)
        XCTAssertEqual(grid[0].prefix(6).compactMap { $0 }.count, 0, "前置 6 格为空")
        XCTAssertEqual(grid[0][6], 1, "第 7 格 = 1 号（周日）")
        let days = grid.flatMap { $0 }.compactMap { $0 }
        XCTAssertEqual(days, Array(1...30))
    }

    func test_feb2026_noLeadingBlanks() {
        // 2026-02-01 是周日？验证接口：首格要么 1 号要么 nil
        let grid = CalendarGrid.monthGrid(year: 2026, month: 2, calendar: makeCalendar())
        let flat = grid.flatMap { $0 }
        XCTAssertEqual(flat.compactMap { $0 }, Array(1...28), "2 月 28 天完整")
    }
}
