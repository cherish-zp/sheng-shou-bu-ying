import Foundation

/// 滚动帧捕获调度器：静止检测 + 最大延迟上限。
///
/// 纯逻辑组件，时钟与定时器均可注入，便于单测。须在主线程使用。
///
/// 调度规则：
/// 1. **静止检测**：滚轮事件到达（`scrollActivityOccurred()`）→ 重置「静止定时器」，
///    事件静默 `stillInterval` 秒后触发一次 `onCaptureNeeded`（App 层在此截帧）。
/// 2. **防饿死上限**：自上次实际截帧起最长 `maxDelay` 秒必强制截帧。
///    惯性滚动期间事件流约 16ms 一个，若只靠静止定时器会被无限重置，
///    导致一次快速甩动只截 1 帧、帧间滚动量超过帧高（内容物理性丢失，任何拼接算法救不回）。
///
/// App 层接线约定：
/// - `schedule` / `cancelScheduled` 由 App 层用 DispatchWorkItem 实现；
/// - `onCaptureNeeded` 回调中调用 `controller.captureFrame()`，完成后调用
///   `captureDidPerform()` 重置 maxDelay 基准（无论是否去重成功都应调用）；
/// - 外层 finish 前的末帧补拍约定见 `ScrollCaptureController` 文档注释。
public final class ScrollCaptureScheduler {

    // MARK: - 配置

    /// 事件静默多久视为「滚动停止」，届时触发一次截帧回调。
    public let stillInterval: TimeInterval
    /// 自上次实际截帧起的最长等待；超过即强制截帧（防止持续滚动饿死防抖定时器）。
    public let maxDelay: TimeInterval

    private let now: () -> TimeInterval
    private let schedule: (_ delay: TimeInterval, _ fire: @escaping () -> Void) -> Void
    private let cancelScheduled: () -> Void

    /// 调度器决定「应截帧」时回调（App 层在此截帧）。
    public var onCaptureNeeded: (() -> Void)?

    // MARK: - 状态

    /// 是否有未触发的静止定时器（末帧补拍判断依据）。
    public var isPending: Bool { hasPendingTimer }
    private var hasPendingTimer = false

    /// maxDelay 基准：上次实际截帧时刻；nil = 尚无基准（首次滚动活动时建立）。
    private var lastCaptureTime: TimeInterval?

    /// - Parameters:
    ///   - stillInterval: 事件静默多久后截帧（默认 80ms，取代旧的 60ms 取消式防抖）。
    ///   - maxDelay: 自上次实际截帧起的最长延迟上限（默认 250ms）。
    ///   - now: 可注入时钟（测试用虚拟时钟）。
    ///   - schedule: App 层注入的定时器注册（DispatchWorkItem 实现）。
    ///   - cancelScheduled: App 层注入的定时器取消。
    public init(stillInterval: TimeInterval = 0.08,
                maxDelay: TimeInterval = 0.25,
                now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
                schedule: @escaping (_ delay: TimeInterval, _ fire: @escaping () -> Void) -> Void,
                cancelScheduled: @escaping () -> Void) {
        self.stillInterval = stillInterval
        self.maxDelay = maxDelay
        self.now = now
        self.schedule = schedule
        self.cancelScheduled = cancelScheduled
    }

    // MARK: - 输入

    /// 每个滚轮事件调用：重置静止定时器；若自上次实际截帧已达 maxDelay 则立即强制截帧。
    public func scrollActivityOccurred() {
        // 首次活动：建立 maxDelay 基准
        if lastCaptureTime == nil {
            lastCaptureTime = now()
        }
        // 防饿死：自上次实际截帧已达上限 → 立即强制截帧
        if let base = lastCaptureTime, now() - base >= maxDelay {
            forceCaptureNow()
        }
        scheduleStillTimer()
    }

    /// App 层截帧完成后调用：重置 maxDelay 基准。
    public func captureDidPerform() {
        lastCaptureTime = now()
    }

    /// 取消未触发的静止定时器（外层 finish 时先查 `isPending` 做末帧补拍，再调它）。
    public func cancelPending() {
        guard hasPendingTimer else { return }
        hasPendingTimer = false
        cancelScheduled()
    }

    /// 立即触发一次截帧回调（若有 pending 静止定时器先取消，避免随后重复触发）。
    public func forceCaptureNow() {
        if hasPendingTimer {
            hasPendingTimer = false
            cancelScheduled()
        }
        // 强制截帧本身也是一次实际截帧，重置 maxDelay 基准
        lastCaptureTime = now()
        onCaptureNeeded?()
    }

    // MARK: - 内部

    /// （重）安排静止定时器：同一时刻至多一个在飞定时器。
    private func scheduleStillTimer() {
        if hasPendingTimer {
            hasPendingTimer = false
            cancelScheduled()
        }
        hasPendingTimer = true
        schedule(stillInterval) { [weak self] in
            // 防御：已被取消/替换的旧闭包不得触发（App 层 cancel 应已拦截，此处兜底）
            guard let self = self, self.hasPendingTimer else { return }
            self.hasPendingTimer = false
            // 静止截帧 = 实际截帧，重置 maxDelay 基准
            self.lastCaptureTime = self.now()
            self.onCaptureNeeded?()
        }
    }
}
