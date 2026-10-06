import AppKit
import CoreGraphics

/// 滚动截图控制器（v2 契约）：管理截帧、会话状态与拼接。
/// 采集节奏由 Coordinator 驱动：滚轮事件 + `ScrollCaptureScheduler` 静止检测调度截帧，
/// 自动模式由 `ScrollAutoScroller` 发送滚轮并喂给 Scheduler；本类只负责帧序列、
/// 内存预算（收敛在会话内）与图像运算。帧相关的会话状态全部在主线程访问。
///
/// **末帧补拍约定**（配合 ScrollCaptureScheduler）：
/// 外层 finish 前若 Scheduler 尚有未触发的静止定时器，必须先补拍一帧再取消，
/// 否则取消 pending 会让末帧永远丢失（成图缺最后一屏）：
///
///     if scheduler.isPending {
///         controller.captureFrame()   // 末帧补拍：捕获最终静止视口
///         scheduler.cancelPending()
///     }
final class ScrollCaptureController {

    /// 会话状态机（值类型）：外部经下方只读转发属性拿到的是实时快照，
    /// 状态推进（tryAdd/start/stop 的 mutating）收敛在本类内进行。
    private(set) var session = ScrollCaptureSession()
    let displayID: CGDirectDisplayID
    let captureRect: CGRect
    let scaleFactor: CGFloat
    /// 截帧时要排除的窗口 ID（选区边框窗口）：只采「边框以下」的窗口，排除自身 UI。
    let excludeWindowID: CGWindowID?

    /// 既有构造器：先建控制器，excludeWindowID 稍后可由外部设置（保留兼容）。
    init(displayID: CGDirectDisplayID, captureRect: CGRect, scaleFactor: CGFloat) {
        self.displayID = displayID
        self.captureRect = captureRect
        self.excludeWindowID = nil
        self.scaleFactor = scaleFactor
    }

    /// v2 契约构造器：构造时即指定要排除的自身 UI 窗口（选区边框）。
    init(captureRect: CGRect, displayID: CGDirectDisplayID, excludeWindowID: CGWindowID?, scaleFactor: CGFloat) {
        self.displayID = displayID
        self.captureRect = captureRect
        self.excludeWindowID = excludeWindowID
        self.scaleFactor = scaleFactor
    }

    // MARK: - 会话状态只读转发（session 为值类型，转发保证拿到实时快照）

    var frameCount: Int { session.count }
    var state: ScrollCaptureSession.State { session.state }
    var mode: ScrollCaptureSession.Mode? { session.mode }
    var isDone: Bool { session.isDone }
    var frames: [CGImage] { session.frames }
    var lastFrame: CGImage? { session.frames.last }
    /// 终止原因：none / userRequested / budgetReached / bottomReached。
    var stopReason: ScrollCaptureStopReason { session.stopReason }
    /// 是否已滚动到底（仅 auto 模式；manual 恒 false）。
    var isAtBottom: Bool { session.isAtBottom }
    /// 是否因内存预算触顶终止。
    var reachedBudgetLimit: Bool { stopReason == .budgetReached }
    /// 终止原因可读描述（DiagLog 埋点用）。
    var stopReasonText: String {
        switch session.stopReason {
        case .none: return "none"
        case .userRequested: return "userRequested"
        case .budgetReached: return "budgetReached(达内存预算)"
        case .bottomReached: return "bottomReached(自动滚动到底)"
        }
    }

    // MARK: - 会话控制

    /// 开始自动滚动截取。
    func startAuto() { session.startAuto() }

    /// 开始手动滚动截取（鼠标滚动触发）。
    func startManual() { session.startManual() }

    /// 停止截取。
    func stop() { session.stop() }

    /// 截取当前选区帧，内容变化时加入序列。返回是否实际加入（去重/预算拒绝/截帧失败均为 false）。
    @discardableResult
    func captureFrame() -> Bool {
        let frame: CGImage?
        if let excludeID = excludeWindowID {
            let bounds = CGDisplayBounds(displayID)
            let globalRect = ScrollCaptureSession.globalCaptureRect(
                displayRect: captureRect, displayBounds: bounds)
            frame = CGWindowListCreateImage(globalRect, .optionOnScreenBelowWindow, excludeID, [.bestResolution])
        } else {
            frame = CGDisplayCreateImage(displayID, rect: captureRect)
        }
        guard let img = frame else {
            DiagLog.write("ScrollCapture: frame capture returned nil")
            return false
        }
        return session.tryAdd(img) == .added
    }

    // MARK: - 拼接（CGImage 运算无主线程要求，可在后台队列调用）

    /// v2 契约：调 `ScrollStitcher.stitch(images:config:)` 拼接全部帧，
    /// 返回结构化 outcome（含 issues、失败边界与固定带高度），不再直接返回 NSImage?。
    func stitch() -> ScrollStitchOutcome {
        let outcome = ScrollStitcher.stitch(images: session.frames, config: .standard)
        // 埋点：拼接结果全貌（成图 nil、失败边界数、固定带高度）供 diag.log 定位质量问题
        let sizeText = outcome.image.map { "\($0.width)x\($0.height)px" } ?? "nil"
        DiagLog.write("ScrollCapture.stitch: frames=\(session.count) image=\(sizeText) "
            + "issues=\(outcome.issues.count) failures=\(outcome.failures.count) "
            + "fixedBand=\(outcome.fixedTopBandHeight)px stopReason=\(stopReasonText)")
        return outcome
    }

    /// v2 契约：强制堆叠——调 `ScrollStitcher.stitchSequential`，
    /// 忽略重叠检测逐帧堆叠输出完整长图（供结果不完整时用户强制导出）。
    func stitchForced() -> CGImage? {
        guard let image = ScrollStitcher.stitchSequential(images: session.frames) else {
            DiagLog.write("ScrollCapture.stitchForced: failed, frames=\(session.count)")
            return nil
        }
        DiagLog.write("ScrollCapture.stitchForced: frames=\(session.count) image=\(image.width)x\(image.height)px")
        return image
    }

    /// 用 scaleFactor 把 CGImage 组装为点尺寸 NSImage（像素 -> 点换算，供 Coordinator 渲染）。
    func renderImage(_ cgImage: CGImage) -> NSImage {
        let displaySize = SelectionRect.pointSize(
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            scaleFactor: scaleFactor
        )
        return NSImage(cgImage: cgImage, size: displaySize)
    }
}
