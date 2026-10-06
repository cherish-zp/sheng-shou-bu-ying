import XCTest

/// TDD: 滚动帧捕获调度器 —— 静止检测 + 最大延迟上限（防惯性滚动饿死防抖）。
/// 用注入的虚拟时钟 + 记录式定时器，手动推进时间验证调度语义。
final class ScrollCaptureSchedulerTests: XCTestCase {

    // MARK: - 测试替身：虚拟时钟调度器

    /// 单定时器槽的虚拟时钟：与调度器「同一时刻至多一个在飞定时器」的语义对应。
    private final class VirtualTimer {
        let fireTime: TimeInterval
        let fire: () -> Void
        init(fireTime: TimeInterval, fire: @escaping () -> Void) {
            self.fireTime = fireTime
            self.fire = fire
        }
    }

    private final class VirtualClockScheduler {
        private(set) var pending: VirtualTimer?
        private(set) var scheduleCount = 0
        private(set) var cancelCount = 0
        var now: TimeInterval = 0

        func schedule(_ delay: TimeInterval, _ fire: @escaping () -> Void) {
            scheduleCount += 1
            pending = VirtualTimer(fireTime: now + delay, fire: fire)
        }

        func cancelScheduled() {
            cancelCount += 1
            pending = nil
        }

        /// 推进虚拟时间，触发所有到期定时器；触发中新调度的任务若同样到期继续触发。
        /// epsilon 容差：多次「now = fireTime; now + delay」的浮点累计漂移约 1e-15 量级，
        /// 不加容差会让边界 tick 漏触发。
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

    /// 构造被测对象（默认契约参数：stillInterval 0.08 / maxDelay 0.25）。
    private func makeScheduler(_ fake: VirtualClockScheduler,
                               stillInterval: TimeInterval = 0.08,
                               maxDelay: TimeInterval = 0.25) -> ScrollCaptureScheduler {
        ScrollCaptureScheduler(
            stillInterval: stillInterval,
            maxDelay: maxDelay,
            now: { fake.now },
            schedule: { fake.schedule($0, $1) },
            cancelScheduled: { fake.cancelScheduled() }
        )
    }

    // MARK: - 静止检测

    func test_事件静默stillInterval后恰好回调一次() {
        let fake = VirtualClockScheduler()
        let scheduler = makeScheduler(fake)
        var captures: [TimeInterval] = []
        scheduler.onCaptureNeeded = { captures.append(fake.now) }

        scheduler.scrollActivityOccurred()      // t = 0 事件
        XCTAssertTrue(scheduler.isPending, "事件后应有未触发的静止定时器")
        fake.advance(by: 0.079)                 // 未到 stillInterval
        XCTAssertEqual(captures.count, 0, "stillInterval 未到不应回调")
        fake.advance(by: 0.002)                 // t = 0.081，越过分界
        XCTAssertEqual(captures.count, 1, "静默 stillInterval 后应恰好回调 1 次")
        XCTAssertEqual(captures[0], 0.08, accuracy: 0.0001, "回调时刻应为 t = stillInterval")
        fake.advance(by: 5.0)                   // 长时间静默，不得再回调
        XCTAssertEqual(captures.count, 1, "回调后无新事件不得重复回调")
        XCTAssertFalse(scheduler.isPending, "触发后不应再有 pending")
    }

    // MARK: - 防饿死上限

    func test_持续事件流按maxDelay强制回调() {
        let fake = VirtualClockScheduler()
        let scheduler = makeScheduler(fake)
        var captures: [TimeInterval] = []
        scheduler.onCaptureNeeded = { captures.append(fake.now) }

        // 模拟惯性滚动：每 16ms 一个事件，持续约 1.0s（事件流期间静止定时器始终被重置）
        var forcedCount = 0
        var lastForced: TimeInterval?
        for _ in 0..<62 {
            scheduler.scrollActivityOccurred()
            if captures.count > forcedCount, let lastCap = captures.last {
                if let last = lastForced, lastCap - last >= 0.25 - 0.001 { forcedCount += 1 }
                if lastForced == nil && lastCap > 0.2 { forcedCount += 1 }
                lastForced = lastCap
            }
            fake.advance(by: 0.016)
        }
        fake.advance(by: 0.1)                   // 事件流结束，让静止定时器触发

        // 1s 的 16ms 事件流：强制回调约 3 次（t≈0.256/0.512/0.768），末尾静止回调 1 次
        XCTAssertEqual(forcedCount, 3, "1s 的 16ms 事件流应强制回调 3 次")
        XCTAssertEqual(captures.count, 4, "总回调 = 3 次强制 + 1 次静止")
        for i in 1..<captures.count {
            let gap = captures[i] - captures[i - 1]
            XCTAssertTrue(gap >= 0.25 - 0.005 || i == captures.count - 1,
                          "强制回调间隔应 >= maxDelay（实际 \(gap)）")
        }
        XCTAssertGreaterThanOrEqual(captures.last ?? 0, 0.95, "末次静止回调应发生在事件流结束之后")
    }

    func test_captureDidPerform重置maxDelay基准() {
        let fake = VirtualClockScheduler()
        let scheduler = makeScheduler(fake)
        var count = 0
        scheduler.onCaptureNeeded = { count += 1 }

        // 阶段一：0.24s 事件流（未达 maxDelay）→ 静止截帧 → captureDidPerform
        for _ in 0..<15 {
            scheduler.scrollActivityOccurred()
            fake.advance(by: 0.016)
        }
        fake.advance(by: 0.1)
        XCTAssertEqual(count, 1, "0.24s 流未达 maxDelay，仅静止回调 1 次")
        scheduler.captureDidPerform()           // 重置基准

        // 阶段二：重置后再滚 0.24s → 不得触发强制回调
        for _ in 0..<15 {
            scheduler.scrollActivityOccurred()
            fake.advance(by: 0.016)
        }
        XCTAssertEqual(count, 1, "captureDidPerform 重置基准后 0.24s 内不得强制回调")
        fake.advance(by: 0.1)
        XCTAssertEqual(count, 2, "静止后第 2 次回调（末帧）")

        // 阶段三：接着再滚 0.26s 不截帧 → 应触发强制回调
        for _ in 0..<16 {
            scheduler.scrollActivityOccurred()
            fake.advance(by: 0.016)
        }
        XCTAssertEqual(count, 3, "自上次截帧超过 maxDelay 应强制回调")
    }

    // MARK: - 取消与强制

    func test_cancelPending后不再回调() {
        let fake = VirtualClockScheduler()
        let scheduler = makeScheduler(fake)
        var count = 0
        scheduler.onCaptureNeeded = { count += 1 }

        scheduler.scrollActivityOccurred()
        XCTAssertTrue(scheduler.isPending, "取消前应 pending")
        scheduler.cancelPending()
        XCTAssertFalse(scheduler.isPending, "取消后不应 pending")
        fake.advance(by: 10.0)
        XCTAssertEqual(count, 0, "cancelPending 后不得再回调")
    }

    func test_forceCaptureNow立即回调且不重复() {
        let fake = VirtualClockScheduler()
        let scheduler = makeScheduler(fake)
        var captures: [TimeInterval] = []
        scheduler.onCaptureNeeded = { captures.append(fake.now) }

        scheduler.scrollActivityOccurred()      // 有 pending 静止定时器
        scheduler.forceCaptureNow()
        XCTAssertEqual(captures.count, 1, "forceCaptureNow 应立即回调")
        XCTAssertEqual(captures[0], 0.0, accuracy: 0.0001, "立即 = 当前时刻 t=0")
        XCTAssertFalse(scheduler.isPending, "forceCaptureNow 应先取消 pending")
        fake.advance(by: 10.0)
        XCTAssertEqual(captures.count, 1, "后续不得重复回调")
    }

    // MARK: - isPending 状态流转

    func test_isPending状态流转() {
        let fake = VirtualClockScheduler()
        let scheduler = makeScheduler(fake)
        scheduler.onCaptureNeeded = {}
        XCTAssertFalse(scheduler.isPending, "初始无 pending")
        scheduler.scrollActivityOccurred()
        XCTAssertTrue(scheduler.isPending, "事件后 pending")
        scheduler.scrollActivityOccurred()      // 重置，仍 pending
        XCTAssertTrue(scheduler.isPending, "重复事件仍 pending")
        XCTAssertEqual(fake.scheduleCount - fake.cancelCount, 1, "同一时刻至多一个在飞定时器")
        fake.advance(by: 0.08)
        XCTAssertFalse(scheduler.isPending, "定时器触发后 pending 消失")
        scheduler.scrollActivityOccurred()
        scheduler.cancelPending()
        XCTAssertFalse(scheduler.isPending, "cancelPending 后 pending 消失")
    }
}
