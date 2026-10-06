import Foundation

/// 自动滚动档位：慢 / 中 / 快。
public enum ScrollAutoSpeedLevel: Int, CaseIterable {
    case slow = 0
    case medium = 1
    case fast = 2
}

/// 单档自动滚动参数。
public struct ScrollAutoSpeed: Equatable {
    /// 每 tick 发送的滚动像素。正值语义 = 向下滚动（内容上移、新内容出现在底部）；
    /// CGEvent wheel1 需要负值表示向下，取负由 App 层处理并注释说明。
    public let pixelsPerTick: Int
    /// tick 间隔（秒）。
    public let tickInterval: TimeInterval

    public init(pixelsPerTick: Int, tickInterval: TimeInterval) {
        self.pixelsPerTick = pixelsPerTick
        self.tickInterval = tickInterval
    }
}

/// 档位参数表。
///
/// 档位（像素速度约）：slow 30px/0.30s ≈ 100px/s、medium 60px/0.20s = 300px/s、fast 90px/0.15s = 600px/s。
///
/// **帧间滚动量约束核验**（配合 ScrollCaptureScheduler.maxDelay = 0.25s）：
/// fast 档单个 tick 90px，maxDelay 窗口内至多发生 ⌈0.25/0.15⌉ = 2 个 tick ≈ 180px；
/// 即便取上限 180px，仍远小于典型帧高（选区高 ≥ 300pt，Retina 2x ≥ 600px），
/// 帧间滚动量 < 60% 帧高（< 360px），相邻帧重叠 ≥ 40%，拼接可恢复。
public enum ScrollAutoSpeedTable {

    /// 返回指定档位的滚动参数。
    public static func speed(for level: ScrollAutoSpeedLevel) -> ScrollAutoSpeed {
        switch level {
        case .slow:
            return ScrollAutoSpeed(pixelsPerTick: 30, tickInterval: 0.30)
        case .medium:
            return ScrollAutoSpeed(pixelsPerTick: 60, tickInterval: 0.20)
        case .fast:
            return ScrollAutoSpeed(pixelsPerTick: 90, tickInterval: 0.15)
        }
    }
}

/// 纯逻辑自动滚动器：按档位节奏周期性调用注入的 `scroll` 闭包（App 层在其中发 CGEvent 滚轮）。
/// 时序由注入的 schedule/cancelScheduled 决定，便于单测。须在主线程使用。
public final class ScrollAutoScroller {

    private let schedule: (_ interval: TimeInterval, _ fire: @escaping () -> Void) -> Void
    private let cancelScheduled: () -> Void
    private let scroll: (_ pixels: Int) -> Void

    /// 是否正在自动滚动。
    public private(set) var isRunning = false
    /// 当前档位（未运行时也可通过 changeSpeed 预设）。
    public private(set) var currentLevel: ScrollAutoSpeedLevel = .slow

    /// 是否有未触发的 tick 定时器。
    private var hasPendingTick = false

    /// - Parameters:
    ///   - schedule: App 层注入的定时器注册（DispatchWorkItem 实现）。
    ///   - cancelScheduled: App 层注入的定时器取消。
    ///   - scroll: App 层注入的滚动动作（发 CGEvent 滚轮，wheel1 取负实现向下滚动）。
    public init(schedule: @escaping (_ interval: TimeInterval, _ fire: @escaping () -> Void) -> Void,
                cancelScheduled: @escaping () -> Void,
                scroll: @escaping (_ pixels: Int) -> Void) {
        self.schedule = schedule
        self.cancelScheduled = cancelScheduled
        self.scroll = scroll
    }

    /// 开始自动滚动：每 tickInterval 调一次 scroll(pixelsPerTick)。
    /// 若已在运行，等价于重启为新档位（不产生双定时器）。
    public func start(level: ScrollAutoSpeedLevel) {
        stopInternal()
        currentLevel = level
        isRunning = true
        scheduleTick()
    }

    /// 运行中换挡：按新档位的 tickInterval 重新计时、tick 像素取新档位。
    /// 未运行时仅记录档位，不启动滚动。
    public func changeSpeed(_ level: ScrollAutoSpeedLevel) {
        currentLevel = level
        guard isRunning else { return }
        scheduleTick()
    }

    /// 停止自动滚动。
    public func stop() {
        stopInternal()
    }

    // MARK: - 内部

    private func stopInternal() {
        guard isRunning || hasPendingTick else { return }
        isRunning = false
        if hasPendingTick {
            hasPendingTick = false
            cancelScheduled()
        }
    }

    /// （重）安排下一个 tick：同一时刻至多一个在飞定时器。
    /// fire 时实时读取 currentLevel，保证换挡后像素值立即生效。
    private func scheduleTick() {
        guard isRunning else { return }
        if hasPendingTick {
            hasPendingTick = false
            cancelScheduled()
        }
        hasPendingTick = true
        let interval = ScrollAutoSpeedTable.speed(for: currentLevel).tickInterval
        schedule(interval) { [weak self] in
            // 防御：已被取消/替换的旧闭包不得触发
            guard let self = self, self.isRunning, self.hasPendingTick else { return }
            self.hasPendingTick = false
            self.scroll(ScrollAutoSpeedTable.speed(for: self.currentLevel).pixelsPerTick)
            // scroll 回调中可能调用了 stop()，此时不再续排
            if self.isRunning {
                self.scheduleTick()
            }
        }
    }
}
