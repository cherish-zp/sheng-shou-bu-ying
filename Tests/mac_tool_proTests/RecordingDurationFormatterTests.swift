import XCTest

/// TDD: 录屏时长格式化 - mm:ss（≥1h 则 h:mm:ss）边界 + 可注入时钟的秒表（暂停冻结）。
final class RecordingDurationFormatterTests: XCTestCase {

    // MARK: - 格式化边界

    func test_format_boundaries() {
        XCTAssertEqual(RecordingDurationFormatter.format(0), "00:00")
        XCTAssertEqual(RecordingDurationFormatter.format(1), "00:01")
        XCTAssertEqual(RecordingDurationFormatter.format(59), "00:59")
        XCTAssertEqual(RecordingDurationFormatter.format(60), "01:00")
        XCTAssertEqual(RecordingDurationFormatter.format(61), "01:01")
        XCTAssertEqual(RecordingDurationFormatter.format(3599), "59:59")
        XCTAssertEqual(RecordingDurationFormatter.format(3600), "1:00:00")
        XCTAssertEqual(RecordingDurationFormatter.format(3661), "1:01:01")
        XCTAssertEqual(RecordingDurationFormatter.format(36000 + 601), "10:10:01")
    }

    func test_format_timeInterval_floorsFractionalSeconds() {
        XCTAssertEqual(RecordingDurationFormatter.format(TimeInterval(59.9)), "00:59")
        XCTAssertEqual(RecordingDurationFormatter.format(TimeInterval(60.0)), "01:00")
        XCTAssertEqual(RecordingDurationFormatter.format(TimeInterval(-3)), "00:00", "负值夹取为 0")
    }

    // MARK: - 秒表（可注入时钟）

    func test_stopwatch_elapsed_countsWhileRunning() {
        var now = Date(timeIntervalSince1970: 1000)
        let sw = RecordingStopwatch(now: { now })
        sw.start()
        now = Date(timeIntervalSince1970: 1010)
        XCTAssertEqual(sw.elapsed, 10, accuracy: 0.001)
    }

    func test_stopwatch_pause_freezesElapsed() {
        var now = Date(timeIntervalSince1970: 1000)
        let sw = RecordingStopwatch(now: { now })
        sw.start()
        now = Date(timeIntervalSince1970: 1012)
        XCTAssertTrue(sw.pause())
        XCTAssertEqual(sw.elapsed, 12, accuracy: 0.001)
        // 暂停期间时钟继续走，但 elapsed 冻结
        now = Date(timeIntervalSince1970: 1030)
        XCTAssertEqual(sw.elapsed, 12, accuracy: 0.001)
    }

    func test_stopwatch_resume_continuesAccumulating() {
        var now = Date(timeIntervalSince1970: 1000)
        let sw = RecordingStopwatch(now: { now })
        sw.start()
        now = Date(timeIntervalSince1970: 1012)
        sw.pause()
        now = Date(timeIntervalSince1970: 1030) // 暂停 18s 不计入
        XCTAssertTrue(sw.resume())
        now = Date(timeIntervalSince1970: 1033)
        XCTAssertEqual(sw.elapsed, 15, accuracy: 0.001)
    }

    func test_stopwatch_pauseResume_rejectedInWrongState() {
        var now = Date(timeIntervalSince1970: 1000)
        let sw = RecordingStopwatch(now: { now })
        XCTAssertFalse(sw.pause(), "未开始不能暂停")
        sw.start()
        XCTAssertFalse(sw.resume(), "运行中不能 resume")
        XCTAssertTrue(sw.pause())
        XCTAssertFalse(sw.pause(), "重复 pause 拒绝")
        XCTAssertTrue(sw.resume())
        XCTAssertFalse(sw.resume(), "重复 resume 拒绝")
    }

    func test_stopwatch_start_restartsFromZero() {
        var now = Date(timeIntervalSince1970: 1000)
        let sw = RecordingStopwatch(now: { now })
        sw.start()
        now = Date(timeIntervalSince1970: 1010)
        sw.start() // 重新开始
        XCTAssertEqual(sw.elapsed, 0, accuracy: 0.001)
        now = Date(timeIntervalSince1970: 1015)
        XCTAssertEqual(sw.elapsed, 5, accuracy: 0.001)
    }

    func test_stopwatch_reset_backsToZeroNotStarted() {
        var now = Date(timeIntervalSince1970: 1000)
        let sw = RecordingStopwatch(now: { now })
        sw.start()
        now = Date(timeIntervalSince1970: 1005)
        sw.reset()
        XCTAssertEqual(sw.elapsed, 0, accuracy: 0.001)
        now = Date(timeIntervalSince1970: 1009)
        XCTAssertEqual(sw.elapsed, 0, accuracy: 0.001, "reset 后不再计时")
        XCTAssertFalse(sw.pause(), "reset 后处于未开始状态")
    }

    func test_stopwatch_pauseBeforeStart_zeroElapsed() {
        let sw = RecordingStopwatch()
        XCTAssertEqual(sw.elapsed, 0)
    }
}
