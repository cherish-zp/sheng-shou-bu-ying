import CoreGraphics

/// 滚动截图会话配置：内存预算与到底判定。
public struct ScrollCaptureSessionConfig {
    /// 帧缓冲内存预算（Σ w*h*4）。触顶后 tryAdd 返回 budgetRejected 并终止会话。
    /// 取代 v1 的 maxFrames=30 硬上限——动画误报帧只占内存、不再烧掉截取机会。
    public var maxBufferBytes: Int
    /// auto 模式连续 N 帧无新增（内容未变化）→ 判到底。
    public var bottomStillFrames: Int

    public init(maxBufferBytes: Int = 512 * 1024 * 1024, bottomStillFrames: Int = 3) {
        self.maxBufferBytes = maxBufferBytes
        self.bottomStillFrames = bottomStillFrames
    }
}

/// 会话终止原因。
public enum ScrollCaptureStopReason: Equatable {
    case none
    case userRequested
    case budgetReached
    case bottomReached
}

/// tryAdd 结果。
public enum FrameAddResult: Equatable {
    case added
    case unchanged
    case budgetRejected
}

/// 滚动截图会话状态机：管理滚动截取的帧序列与模式。
///
/// 状态流转：ready（工具栏已显示，等待开始）→ capturing（截帧中）→ done（已停止，待拼接）。
/// 模式：auto（自动滚动，点"开始"触发）、manual（手动滚动，鼠标滚动触发）。
/// 纯逻辑，便于单测。
public struct ScrollCaptureSession {
    public enum State: Equatable {
        case ready
        case capturing
        case done
    }

    public enum Mode: Equatable {
        case auto
        case manual
    }

    public private(set) var frames: [CGImage] = []
    public private(set) var state: State = .ready
    public private(set) var mode: Mode?
    /// 帧数上限。新代码应依赖 config.maxBufferBytes 预算；此字段保留兼容
    /// v1 的 init(maxFrames:) 语义，默认 Int.max（不限制）。
    public let maxFrames: Int
    public let config: ScrollCaptureSessionConfig

    /// 终止原因：stop() → userRequested；预算触顶 → budgetReached；
    /// auto 连续 bottomStillFrames 帧无新增 → bottomReached。
    public private(set) var stopReason: ScrollCaptureStopReason = .none
    /// 已接收帧的字节总量（Σ w*h*4）。
    public private(set) var bufferBytes: Int = 0
    /// 连续 unchanged 计数（added 即清零）。
    private var unchangedStreak = 0

    /// 自动滚动 delta：负值 = 向下滚动（内容上移、新内容出现在底部），
    /// 用于长截图自动滚动模式。
    public static let autoScrollDelta: Int32 = -30

    /// 默认初始化：字节预算管理，不设帧数上限。
    public init(config: ScrollCaptureSessionConfig = .init(), maxFrames: Int = .max) {
        self.config = config
        self.maxFrames = maxFrames
    }

    public var count: Int { frames.count }
    public var isFull: Bool { frames.count >= maxFrames }
    public var isDone: Bool { state == .done }

    /// 是否已滚动到底：仅 auto 模式，连续 bottomStillFrames 帧无新增 → true；manual 恒 false。
    public var isAtBottom: Bool {
        mode == .auto && unchangedStreak >= config.bottomStillFrames
    }

    /// 开始自动滚动截取。仅在 ready 状态有效。
    public mutating func startAuto() {
        guard state == .ready else { return }
        mode = .auto
        state = .capturing
    }

    /// 开始手动滚动截取（鼠标滚动触发）。仅在 ready 状态有效。
    public mutating func startManual() {
        guard state == .ready else { return }
        mode = .manual
        state = .capturing
    }

    /// 尝试添加一帧。仅在 capturing 状态有效；首帧总是添加，后续帧仅在内容变化时添加。
    /// - 预算不足（当前缓冲 + 该帧 > maxBufferBytes）→ budgetRejected，会话终止（budgetReached）。
    /// - auto 模式下连续 bottomStillFrames 帧无新增 → 判到底，会话终止（bottomReached）。
    /// - 非 capturing 状态下不添加，返回 unchanged。
    @discardableResult
    public mutating func tryAdd(_ frame: CGImage) -> FrameAddResult {
        guard state == .capturing else { return .unchanged }
        let frameBytes = frame.width * frame.height * 4
        guard bufferBytes + frameBytes <= config.maxBufferBytes else {
            state = .done
            stopReason = .budgetReached
            return .budgetRejected
        }
        if frames.isEmpty {
            accept(frame, bytes: frameBytes)
            return .added
        }
        guard !isFull else {
            state = .done
            return .unchanged
        }
        if ScrollStitcher.contentChanged(frames.last!, frame) {
            accept(frame, bytes: frameBytes)
            return .added
        }
        unchangedStreak += 1
        if mode == .auto && unchangedStreak >= config.bottomStillFrames {
            state = .done
            stopReason = .bottomReached
        }
        return .unchanged
    }

    /// 停止截取，转为 done 状态。已终止的会话（预算/到底自动终止）保留原终止原因。
    public mutating func stop() {
        guard state != .done else { return }
        state = .done
        stopReason = .userRequested
    }

    // MARK: - 私有

    private mutating func accept(_ frame: CGImage, bytes: Int) {
        frames.append(frame)
        bufferBytes += bytes
        unchangedStreak = 0
        if isFull { state = .done }
    }
}

extension ScrollCaptureSession {
    /// 将选区从视图坐标（左下原点）转为显示器坐标（左上原点），
    /// 用于 CGDisplayCreateImage 的 rect 参数。
    public static func displayCaptureRect(viewRect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x: viewRect.origin.x,
               y: screenHeight - viewRect.maxY,
               width: viewRect.width,
               height: viewRect.height)
    }

    /// 将显示器坐标（相对于显示器左上角）转为全局屏幕坐标（左上原点），
    /// 用于 CGWindowListCreateImage 的 rect 参数（支持多屏偏移）。
    public static func globalCaptureRect(displayRect: CGRect, displayBounds: CGRect) -> CGRect {
        CGRect(x: displayBounds.origin.x + displayRect.origin.x,
               y: displayBounds.origin.y + displayRect.origin.y,
               width: displayRect.width,
               height: displayRect.height)
    }
}
