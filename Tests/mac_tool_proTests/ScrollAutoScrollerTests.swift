import XCTest

/// TDD: 纯逻辑自动滚动器 —— 档位参数表、tick 调度、运行中换挡、停止语义。
/// 用注入的虚拟时钟手动推进时间，验证节奏与档位切换。
final class ScrollAutoScrollerTests: XCTestCase {

    // MARK: - 测试替身

    private final class VirtualTimer2 {
        let fireTime: TimeInterval
        let fire: () -> Void
        init(fireTime: TimeInterval, fire: @escaping () -> Void) {
            self.fireTime = fireTime
            self.fire = fire
        }
    }

    private final class VirtualClockScheduler2 {
        private(set) var pending: VirtualTimer2?
        private(set) var cancelCount = 0
        var now: TimeInterval = 0

        func schedule(_ delay: TimeInterval, _ fire: @escaping () -> Void) {
            pending = VirtualTimer2(fireTime: now + delay, fire: fire)
        }

        func cancelScheduled() {
            cancelCount += 1
            pending = nil
        }

        /// epsilon 容差：规避多次「now = fireTime; now + delay」的浮点累计漂移。
        func advance(by interval: TimeInterval) {
            let target = now + interval
            while let p = pending, p.fireTime <= target + 1e-9 {
                now = max(p.fireTime, now)
                let f = p.fire
                pending = nil
                f()
            }
            now = target
        }
    }

    /// 滚动调用记录器（引用类型：逃逸闭包内可安全追加）。
    private final class ScrollRecorder {
        var pixels: [Int] = []
    }

    private func makeScroller(_ fake: VirtualClockScheduler2, _ recorder: ScrollRecorder) -> ScrollAutoScroller {
        ScrollAutoScroller(
            schedule: { fake.schedule($0, $1) },
            cancelScheduled: { fake.cancelScheduled() },
            scroll: { recorder.pixels.append($0) }
        )
    }

    // MARK: - 档位参数表

    func test_档位参数表值() {
        // 档位契约：slow 30px/0.30s(100px/s)、medium 60px/0.20s(300px/s)、fast 90px/0.15s(600px/s)
        XCTAssertEqual(ScrollAutoSpeedTable.speed(for: .slow),
                       ScrollAutoSpeed(pixelsPerTick: 30, tickInterval: 0.30), "slow 档 30px/0.30s")
        XCTAssertEqual(ScrollAutoSpeedTable.speed(for: .medium),
                       ScrollAutoSpeed(pixelsPerTick: 60, tickInterval: 0.20), "medium 档 60px/0.20s")
        XCTAssertEqual(ScrollAutoSpeedTable.speed(for: .fast),
                       ScrollAutoSpeed(pixelsPerTick: 90, tickInterval: 0.15), "fast 档 90px/0.15s")
        XCTAssertEqual(ScrollAutoSpeedLevel.allCases.count, 3, "共 3 个档位")
        XCTAssertEqual(ScrollAutoSpeedLevel(rawValue: 0), .slow, "rawValue 0 = slow")
        XCTAssertEqual(ScrollAutoSpeedLevel(rawValue: 1), .medium, "rawValue 1 = medium")
        XCTAssertEqual(ScrollAutoSpeedLevel(rawValue: 2), .fast, "rawValue 2 = fast")
    }

    /// 设计约束核验：fast 档 × maxDelay 0.25s 内的滚动量须远小于 60% 典型帧高，
    /// 保证任意两帧间滚动量可恢复（选区高 >= 300pt，Retina 2x 帧高 >= 600px）。
    func test_帧间滚动量约束_不超过典型帧高六成() {
        let fast = ScrollAutoSpeedTable.speed(for: .fast)
        let maxDelay: TimeInterval = 0.25
        // maxDelay 窗口内至多 ⌈maxDelay / tickInterval⌉ 个 tick
        let ticksInWindow = Int(ceil(maxDelay / fast.tickInterval))
        let maxScrollBetweenFrames = fast.pixelsPerTick * ticksInWindow
        let typicalFrameHeight = 600.0   // 300pt × Retina 2x
        XCTAssertLessThanOrEqual(Double(maxScrollBetweenFrames), typicalFrameHeight * 0.6,
                                 "fast 档 maxDelay 窗口滚动 \(maxScrollBetweenFrames)px 应 <= 60% 帧高（360px）")
        // 速度档位核验
        XCTAssertEqual(Int((Double(fast.pixelsPerTick) / fast.tickInterval).rounded()), 600, "fast ≈ 600px/s")
    }

    // MARK: - tick 调度

    func test_start后按tickInterval触发scroll() {
        let fake = VirtualClockScheduler2()
        let recorder = ScrollRecorder()
        let scroller = makeScroller(fake, recorder)
        XCTAssertFalse(scroller.isRunning, "初始未运行")

        scroller.start(level: .medium)
        XCTAssertTrue(scroller.isRunning, "start 后运行中")
        XCTAssertEqual(scroller.currentLevel, .medium, "currentLevel = medium")

        fake.advance(by: 0.199)
        XCTAssertEqual(recorder.pixels.count, 0, "start 后首个 tick 前不滚动")
        fake.advance(by: 0.001)             // t = 0.20：第 1 个 tick
        XCTAssertEqual(recorder.pixels, [60], "medium 每 tick 滚 60px")
        fake.advance(by: 0.40)              // t = 0.60：第 2、3 个 tick
        XCTAssertEqual(recorder.pixels, [60, 60, 60], "每 tickInterval 触发一次 scroll(60)")
    }

    // MARK: - 换挡

    func test_changeSpeed运行中换挡生效() {
        let fake = VirtualClockScheduler2()
        let recorder = ScrollRecorder()
        let scroller = makeScroller(fake, recorder)
        scroller.start(level: .slow)
        fake.advance(by: 0.30)              // 第 1 个 slow tick
        XCTAssertEqual(recorder.pixels, [30], "slow 档 tick 滚 30px")

        scroller.changeSpeed(.fast)         // t = 0.30 换挡
        XCTAssertEqual(scroller.currentLevel, .fast, "currentLevel 更新为 fast")
        fake.advance(by: 0.149)
        XCTAssertEqual(recorder.pixels.count, 1, "换挡后按新 tickInterval 重新计时")
        fake.advance(by: 0.001)             // t = 0.45：fast 第 1 tick
        XCTAssertEqual(recorder.pixels, [30, 90], "换挡后 tick 滚 90px")
        fake.advance(by: 0.30)              // t = 0.60 / 0.75：fast 第 2、3 tick
        XCTAssertEqual(recorder.pixels, [30, 90, 90, 90], "fast 档每 0.15s 滚 90px")
    }

    func test_changeSpeed未运行只更新档位且start幂等() {
        let fake = VirtualClockScheduler2()
        let recorder = ScrollRecorder()
        let scroller = makeScroller(fake, recorder)
        scroller.changeSpeed(.fast)         // 未运行：只记录档位
        XCTAssertEqual(scroller.currentLevel, .fast, "未运行换挡只更新档位")
        XCTAssertFalse(scroller.isRunning, "未运行换挡不启动")
        fake.advance(by: 10.0)
        XCTAssertEqual(recorder.pixels.count, 0, "未运行不滚动")

        scroller.start(level: .medium)
        scroller.start(level: .slow)        // 运行中重复 start：重启为 slow，不产生双定时器
        XCTAssertEqual(scroller.currentLevel, .slow, "重复 start 后档位取最新")
        fake.advance(by: 0.60)
        XCTAssertEqual(recorder.pixels, [30, 30], "重复 start 只有单一定时链（2 个 tick）")
    }

    // MARK: - 停止

    func test_stop后不再触发() {
        let fake = VirtualClockScheduler2()
        let recorder = ScrollRecorder()
        let scroller = makeScroller(fake, recorder)
        scroller.start(level: .fast)
        fake.advance(by: 0.15)
        XCTAssertEqual(recorder.pixels.count, 1, "stop 前正常触发")
        XCTAssertEqual(fake.cancelCount, 0, "尚未停止：cancel 仅在换挡/停止时发生")

        scroller.stop()
        XCTAssertFalse(scroller.isRunning, "stop 后未运行")
        fake.advance(by: 10.0)
        XCTAssertEqual(recorder.pixels.count, 1, "stop 后不再触发 scroll")
        scroller.stop()                     // 重复 stop 幂等
        XCTAssertFalse(scroller.isRunning, "重复 stop 幂等")
    }
}
