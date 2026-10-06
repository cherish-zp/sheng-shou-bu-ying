import Foundation

/// 录屏时长格式化：mm:ss，满 1 小时升级为 h:mm:ss。纯函数。
public enum RecordingDurationFormatter {

    /// 格式化整秒。负值夹取为 0。
    public static func format(_ seconds: Int) -> String {
        let total = max(0, seconds)
        if total < 3600 {
            return String(format: "%02d:%02d", total / 60, total % 60)
        }
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// 格式化时间区间（向下取整，避免 59.9s 显示成 01:00）。
    public static func format(_ interval: TimeInterval) -> String {
        format(Int(interval.rounded(.down)))
    }
}

/// 录屏计时秒表：暂停时冻结，可注入时钟便于单测。
/// 线程约定：仅在主线程使用（控制条计时器驱动）。
public final class RecordingStopwatch {

    private let now: () -> Date
    /// 计时锚点（最近一次 start/resume 的时刻）。
    private var anchor: Date?
    /// 暂停时刻（nil = 未暂停）。
    private var pausedAt: Date?
    /// 暂停前已累计的时长。
    private var accumulated: TimeInterval = 0

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// 是否暂停中。
    public var isPaused: Bool { pausedAt != nil }

    /// 已录时长（暂停期间冻结）。未开始返回 0。
    public var elapsed: TimeInterval {
        if let anchor = anchor {
            return accumulated + now().timeIntervalSince(anchor)
        }
        return accumulated
    }

    /// 开始新计时（清零重来）。armed → recording 时调用。
    public func start() {
        anchor = now()
        pausedAt = nil
        accumulated = 0
    }

    /// 暂停（冻结）。仅运行中可暂停。
    @discardableResult
    public func pause() -> Bool {
        guard let anchor = anchor, pausedAt == nil else { return false }
        let pausedTime = now()
        accumulated += pausedTime.timeIntervalSince(anchor)
        pausedAt = pausedTime
        self.anchor = nil
        return true
    }

    /// 恢复。仅暂停中可恢复。
    @discardableResult
    public func resume() -> Bool {
        guard anchor == nil, pausedAt != nil else { return false }
        anchor = now()
        pausedAt = nil
        return true
    }

    /// 复位到未开始。
    public func reset() {
        anchor = nil
        pausedAt = nil
        accumulated = 0
    }
}
