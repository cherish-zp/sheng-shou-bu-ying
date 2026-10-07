import XCTest

/// TDD: 截图配置 - 保存目录/格式/文件名前缀，Codable 便于持久化。
final class ScreenshotConfigTests: XCTestCase {

    func test_defaultConfig_usesPicturesScreenshots() {
        let config = ScreenshotConfig()
        XCTAssertTrue(config.saveDirectory.path.hasSuffix("Pictures/Screenshots"))
        XCTAssertEqual(config.format, .png)
        XCTAssertEqual(config.filenamePrefix, "截屏")
    }

    func test_codableRoundTrip() throws {
        let dir = URL(fileURLWithPath: "/tmp/shots")
        let config = ScreenshotConfig(saveDirectory: dir, format: .jpg, filenamePrefix: "Shot")
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(ScreenshotConfig.self, from: data)
        XCTAssertEqual(back, config)
    }

    func test_fileNameBuilder_defaultFormat() {
        let date = makeDate(year: 2026, month: 8, day: 1, hour: 14, minute: 44, second: 33)
        let name = ScreenshotFileNameBuilder.baseName(date: date, prefix: "截屏", timeZone: Self.tz)
        XCTAssertEqual(name, "截屏 2026-08-01 14.44.33")
    }

    func test_uniqueFileName_dedup() {
        let config = ScreenshotConfig(saveDirectory: URL(fileURLWithPath: "/tmp"))
        let date = makeDate(year: 2026, month: 8, day: 1, hour: 14, minute: 44, second: 33)
        let existing: Set<String> = ["截屏 2026-08-01 14.44.33.png"]
        let name = ScreenshotFileNameBuilder.uniqueFileName(date: date, config: config, existingNames: existing, timeZone: Self.tz)
        XCTAssertEqual(name, "截屏 2026-08-01 14.44.33 2.png")
    }

    func test_uniqueFileName_noConflict() {
        let config = ScreenshotConfig(saveDirectory: URL(fileURLWithPath: "/tmp"))
        let date = makeDate(year: 2026, month: 8, day: 1, hour: 14, minute: 44, second: 33)
        let name = ScreenshotFileNameBuilder.uniqueFileName(date: date, config: config, existingNames: [], timeZone: Self.tz)
        XCTAssertEqual(name, "截屏 2026-08-01 14.44.33.png")
    }

    // MARK: - Helpers

    /// 与 makeDate 的构造时区一致，断言在任意宿主时区（含 CI 的 UTC）下确定。
    private static let tz = TimeZone(identifier: "Asia/Shanghai")!

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
}
