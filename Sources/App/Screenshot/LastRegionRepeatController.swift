import AppKit

/// 「重复上次区域」公共入口控制器：对最近一次成功截图的选区抓当前屏幕新鲜帧裁剪，
/// 直接复制到剪贴板 + Toast，全程无覆盖层 UI。
///
/// 集成接线（AppDelegate 一行调用，无需其他设置）：
///     LastRegionRepeatController.shared.repeatAndCopy()
///
/// 选区记录已由 ScreenshotCoordinator 挂进选区完成/移动路径（UserDefaults 持久化，
/// 跨重启可用）。无记录 / 显示器已拔 / 捕获失败时返回 false（写 diag.log，不弹 UI）。
final class LastRegionRepeatController {

    static let shared = LastRegionRepeatController()

    private let store: LastRegionStore
    private let freshFrames: FreshFrameProvider
    private let feedback: ScreenshotFeedbackPresenter

    init(store: LastRegionStore = LastRegionStore(),
         freshFrames: FreshFrameProvider = FreshFrameProvider(),
         feedback: ScreenshotFeedbackPresenter = ScreenshotFeedbackPresenter()) {
        self.store = store
        self.freshFrames = freshFrames
        self.feedback = feedback
    }

    /// 重复上次截图区域并复制。成功（已复制）返回 true。
    @discardableResult
    func repeatAndCopy() -> Bool {
        guard let record = store.load() else {
            DiagLog.write("LastRegionRepeat: no record, ignore")
            return false
        }
        // 选区所在屏已拔出时不重复（不做跨屏迁移，避免截错内容）
        guard let screen = ScreenDisplayMatcher.screen(withDisplayID: record.displayID) else {
            DiagLog.write("LastRegionRepeat: display \(record.displayID) unavailable, ignore")
            return false
        }
        // 屏幕分辨率可能已变化：把记录 rect 夹取到当前屏内
        let clamped = SelectionRect.clamp(record.rect, to: CGRect(origin: .zero, size: screen.frame.size))
        guard SelectionRect.isValid(clamped, minimum: 10) else {
            DiagLog.write("LastRegionRepeat: record rect invalid on current screen, ignore")
            return false
        }
        guard let cropped = freshFrames.captureCropped(
            selection: clamped, displayID: record.displayID,
            screenPointSize: screen.frame.size) else {
            DiagLog.write("LastRegionRepeat: fresh frame capture failed")
            return false
        }
        let image = NSImage(cgImage: cropped, size: clamped.size)
        let pb = NSPasteboard.general
        pb.clearContents()
        let ok = pb.writeObjects([image])
        if ok {
            feedback.showCopied()
            DiagLog.write("LastRegionRepeat: copied \(cropped.width)x\(cropped.height) px")
        }
        return ok
    }
}
