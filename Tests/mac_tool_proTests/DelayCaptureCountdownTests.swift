import XCTest
import CoreGraphics

/// TDD: 延时截图倒计时状态机 - 每秒 tick、归零 finish、cancel 失效、注入调度可测。
final class DelayCaptureCountdownTests: XCTestCase {

    func test_start_ticksEverySecond_thenFinishes() {
        var scheduled: [(delay: TimeInterval, fire: () -> Void)] = []
        var ticks: [Int] = []
        var finished = 0
        let countdown = DelayCaptureCountdown(
            seconds: 3,
            schedule: { delay, fire in scheduled.append((delay, fire)) },
            cancelScheduled: { scheduled.removeAll() })
        countdown.onTick = { ticks.append($0) }
        countdown.onFinish = { finished += 1 }

        countdown.start()
        XCTAssertEqual(ticks, [3], "start 立即显示满秒数")
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled[0].delay, 1.0, "调度间隔 1 秒")

        scheduled[0].fire()
        XCTAssertEqual(ticks, [3, 2])
        scheduled.last?.fire()
        XCTAssertEqual(ticks, [3, 2, 1])
        scheduled.last?.fire()
        XCTAssertEqual(finished, 1, "归零触发 finish")
        XCTAssertFalse(countdown.isRunning)
    }

    func test_cancel_stopsTickingAndFinishing() {
        var scheduled: [(delay: TimeInterval, fire: () -> Void)] = []
        var ticks: [Int] = []
        var finished = 0
        let countdown = DelayCaptureCountdown(
            seconds: 2,
            schedule: { delay, fire in scheduled.append((delay, fire)) },
            cancelScheduled: { scheduled.removeAll() })
        countdown.onTick = { ticks.append($0) }
        countdown.onFinish = { finished += 1 }

        countdown.start()
        countdown.cancel()
        XCTAssertFalse(countdown.isRunning)
        scheduled.first?.fire()
        XCTAssertEqual(ticks, [2], "cancel 后旧回调失效不再 tick")
        XCTAssertEqual(finished, 0, "cancel 后不 finish")
    }

    func test_oneSecondFinishesAfterSingleFire() {
        var scheduled: [(delay: TimeInterval, fire: () -> Void)] = []
        var finished = 0
        let countdown = DelayCaptureCountdown(
            seconds: 1,
            schedule: { delay, fire in scheduled.append((delay, fire)) },
            cancelScheduled: { scheduled.removeAll() })
        countdown.onFinish = { finished += 1 }
        countdown.start()
        scheduled[0].fire()
        XCTAssertEqual(finished, 1)
    }

    func test_startIsIdempotent() {
        var scheduled: [(delay: TimeInterval, fire: () -> Void)] = []
        let countdown = DelayCaptureCountdown(
            seconds: 3,
            schedule: { delay, fire in scheduled.append((delay, fire)) },
            cancelScheduled: {})
        countdown.start()
        countdown.start()
        XCTAssertEqual(scheduled.count, 1, "重复 start 不叠加调度")
    }

    // MARK: - 倒计时徽章定位

    func test_badgeLayout_centersOnSelection() {
        let frame = CountdownBadgeLayout.frame(
            containerSize: CGSize(width: 1000, height: 800),
            focusRect: CGRect(x: 100, y: 100, width: 200, height: 100))
        XCTAssertEqual(frame.midX, 200)
        XCTAssertEqual(frame.midY, 150)
        XCTAssertEqual(frame.width, CountdownBadgeLayout.badgeSide)
    }

    func test_badgeLayout_centerOfScreenWithoutSelection() {
        let frame = CountdownBadgeLayout.frame(
            containerSize: CGSize(width: 1000, height: 800), focusRect: nil)
        XCTAssertEqual(frame.midX, 500)
        XCTAssertEqual(frame.midY, 400)
    }

    func test_badgeLayout_clampsInsideScreenNearEdges() {
        let frame = CountdownBadgeLayout.frame(
            containerSize: CGSize(width: 1000, height: 800),
            focusRect: CGRect(x: 0, y: 0, width: 30, height: 30))
        XCTAssertGreaterThanOrEqual(frame.minX, 0)
        XCTAssertGreaterThanOrEqual(frame.minY, 0)
        XCTAssertLessThanOrEqual(frame.maxX, 1000)
        XCTAssertLessThanOrEqual(frame.maxY, 800)
    }
}
