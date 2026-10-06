import XCTest

/// TDD: 录屏文件名 - 「录屏 yyyy-MM-dd HH.mm.ss.mp4」，复用 FileNameResolver 去重。
final class RecordingFileNameBuilderTests: XCTestCase {

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    func test_baseName_format() {
        let date = makeDate(year: 2026, month: 10, day: 6, hour: 14, minute: 44, second: 33)
        XCTAssertEqual(RecordingFileNameBuilder.baseName(date: date), "录屏 2026-10-06 14.44.33")
    }

    func test_baseName_customPrefix() {
        let date = makeDate(year: 2026, month: 10, day: 6, hour: 9, minute: 5, second: 7)
        XCTAssertEqual(RecordingFileNameBuilder.baseName(date: date, prefix: "演示"),
                       "演示 2026-10-06 09.05.07")
    }

    func test_uniqueFileName_noConflict() {
        let date = makeDate(year: 2026, month: 10, day: 6, hour: 14, minute: 44, second: 33)
        let name = RecordingFileNameBuilder.uniqueFileName(date: date, existingNames: [])
        XCTAssertEqual(name, "录屏 2026-10-06 14.44.33.mp4")
    }

    func test_uniqueFileName_dedup() {
        let date = makeDate(year: 2026, month: 10, day: 6, hour: 14, minute: 44, second: 33)
        let existing: Set<String> = ["录屏 2026-10-06 14.44.33.mp4"]
        let name = RecordingFileNameBuilder.uniqueFileName(date: date, existingNames: existing)
        XCTAssertEqual(name, "录屏 2026-10-06 14.44.33 2.mp4")
    }

    func test_uniqueFileName_dedupMultiple() {
        let date = makeDate(year: 2026, month: 10, day: 6, hour: 14, minute: 44, second: 33)
        let existing: Set<String> = [
            "录屏 2026-10-06 14.44.33.mp4",
            "录屏 2026-10-06 14.44.33 2.mp4",
            "录屏 2026-10-06 14.44.33 3.mp4",
        ]
        let name = RecordingFileNameBuilder.uniqueFileName(date: date, existingNames: existing)
        XCTAssertEqual(name, "录屏 2026-10-06 14.44.33 4.mp4")
    }
}
