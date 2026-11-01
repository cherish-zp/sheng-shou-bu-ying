import Foundation

/// 轻量日历月网格（纯逻辑，TDD）：给定年月 → 6×7 网格（周一为首），
/// 前后月补位为 nil，当月日期为 1...天数。
public enum CalendarGrid {

    public static func monthGrid(year: Int, month: Int, calendar: Calendar = .current) -> [[Int?]] {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        guard let firstDay = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else { return [] }
        let daysInMonth = range.count
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = (firstWeekday + 5) % 7

        var flat: [Int?] = Array(repeating: nil, count: leadingBlanks)
        for day in 1...daysInMonth { flat.append(day) }
        while flat.count % 7 != 0 { flat.append(nil) }

        var grid: [[Int?]] = []
        for row in 0..<(flat.count / 7) {
            grid.append(Array(flat[row * 7..<(row + 1) * 7]))
        }
        return grid
    }
}
