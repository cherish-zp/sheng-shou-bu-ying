import Foundation

/// 延时截图倒计时状态机：纯逻辑、调度注入（对齐 ScrollCaptureScheduler 的注入惯例），可单测。
/// 节奏：start 立即 onTick(seconds) 并调度 1 秒间隔触发，归零回调 onFinish；cancel 后不再触发。
public final class DelayCaptureCountdown {

    /// 总秒数（3/5/10）。
    public let seconds: Int

    /// 剩余秒数。
    public private(set) var remaining: Int

    /// 是否倒计时中。
    public private(set) var isRunning = false

    /// 每秒回调（参数为剩余秒数，用于更新浮窗数字与 NSSound.beep 等副作用）。
    public var onTick: ((Int) -> Void)?

    /// 倒计时归零回调（抓新鲜帧入口）。
    public var onFinish: (() -> Void)?

    /// 调度注入：delay 秒后触发 fire；cancelScheduled 取消未触发的调度。
    private let schedule: (_ delay: TimeInterval, _ fire: @escaping () -> Void) -> Void
    private let cancelScheduled: () -> Void

    /// 调度代数：cancel 后旧回调失效。
    private var generation = 0

    public init(
        seconds: Int,
        schedule: @escaping (_ delay: TimeInterval, _ fire: @escaping () -> Void) -> Void,
        cancelScheduled: @escaping () -> Void
    ) {
        self.seconds = max(1, seconds)
        self.remaining = self.seconds
        self.schedule = schedule
        self.cancelScheduled = cancelScheduled
    }

    /// 开始倒计时：立即显示满秒数并调度首个 1 秒触发。重复调用为空操作。
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        remaining = seconds
        onTick?(remaining)
        scheduleNextTick()
    }

    /// 取消倒计时：停止调度并使未触发的回调失效。
    public func cancel() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        cancelScheduled()
    }

    private func scheduleNextTick() {
        generation += 1
        let token = generation
        schedule(1.0) { [weak self] in
            guard let self = self, self.isRunning, token == self.generation else { return }
            self.remaining -= 1
            if self.remaining > 0 {
                self.onTick?(self.remaining)
                self.scheduleNextTick()
            } else {
                self.isRunning = false
                self.onFinish?()
            }
        }
    }
}

/// 倒计时浮窗徽章定位：优先取选区中心，贴边时夹取不出屏；无选区取屏幕中心。纯函数可单测。
public enum CountdownBadgeLayout {

    /// 徽章方形边长（视图点）。
    public static let badgeSide: CGFloat = 168

    /// 计算徽章在容器（屏幕本地坐标）中的 rect。
    /// - Parameters:
    ///   - containerSize: 容器（屏幕）点尺寸。
    ///   - focusRect: 选区 rect（容器本地坐标），nil 时取容器中心。
    public static func frame(containerSize: CGSize, focusRect: CGRect?) -> CGRect {
        var center = focusRect.map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        let half = badgeSide / 2
        let margin: CGFloat = 12 + half
        center.x = min(max(center.x, margin), containerSize.width - margin)
        center.y = min(max(center.y, margin), containerSize.height - margin)
        return CGRect(x: center.x - half, y: center.y - half, width: badgeSide, height: badgeSide)
    }
}
