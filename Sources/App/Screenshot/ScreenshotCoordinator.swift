import AppKit
import CoreGraphics
import QuartzCore
import Vision

/// 截图协调器：串联「捕获画面 -> 全屏覆盖层选区 -> 工具条编辑 -> 复制/保存/贴图」全流程。
/// 长截图流程（v2）：ScrollCaptureScheduler 统一截帧调度 + ScrollAutoScroller 自动滚动
/// + ScrollCaptureToolbar 控制工具条 + LiveStitchPreviewView 实时预览 + ScrollResultPanel 结果窗。
final class ScreenshotCoordinator {

    private let captureService = ScreenCaptureService()
    private var overlayWindows: [ScreenshotOverlayWindow] = []
    private var toolbar: ScreenshotToolbar?
    private var pinWindows: [PinWindow] = []
    private var activeOverlay: ScreenshotOverlayWindow?
    private var selectionRect: CGRect?
    /// 画布设置：持久化到 UserDefaults，跨会话/跨重启保持用户所选（圆角/阴影），
    /// 新截图会话开始时同步到覆盖层视图，避免"上次贴 32 这次变 16"的不一致
    private var canvasSettings = CanvasSettingsStore.load() {
        didSet { CanvasSettingsStore.save(canvasSettings) }
    }
    private var ocrResultPanel: NSPanel?
    private var ocrTextView: NSTextView?
    private var escMonitor: Any?
    /// 选区超时定时器：覆盖层显示后若用户长时间未操作（如全屏下覆盖层不可见），自动清理。
    private var idleTimeoutTimer: Timer?
    /// 统一反馈展示器（普通截图与长截图结果窗共用）。
    private let feedback = ScreenshotFeedbackPresenter()
    /// 统一保存服务（普通截图与长截图结果窗共用，成败均有提示，见 ScreenshotSaveService）。
    private lazy var saveService = ScreenshotSaveService(feedback: feedback)

    // MARK: 延时截图 / 重复上次区域 / OCR 增强 状态

    /// 最近一次成功截图选区记录（UserDefaults 持久化，「重复上次区域」数据源）。
    private let lastRegionStore = LastRegionStore()
    /// 新鲜帧捕获 + 裁剪（延时截图结束与重复上次区域共用组件）。
    private let freshFrames = FreshFrameProvider()
    /// 延时倒计时状态机（schedule 注入主队列 DispatchWorkItem）。
    private var delayCountdown: DelayCaptureCountdown?
    private var delayCaptureWorkItem: DispatchWorkItem?
    /// 倒计时浮窗（选区所在屏全屏透明窗，大号数字）。
    private var countdownWindow: ScreenshotCountdownWindow?
    /// 轻量 Toast（自定义文案：静默 OCR「已复制 N 字」等），层级对齐 feedback（screenSaver+3）。
    private var toastPanel: NSPanel?
    private var toastHideWorkItem: DispatchWorkItem?
    private var toastGeneration = 0
    /// OCR 结果面板顶部二维码文本视图（复制按钮取值用）。
    private var ocrQRTextView: NSTextView?

    // MARK: 长截图状态（采集期）

    private var scrollController: ScrollCaptureController?
    /// 选区边框窗口：截帧排除锚点（只采「边框以下」的窗口内容）。
    private var scrollBorderWindow: NSPanel?
    /// 长截图控制工具条（开始/停止、档位、完成、取消）。
    private var scrollToolbar: ScrollCaptureToolbar?
    /// 实时生长预览窗（LiveStitchPreviewView 的宿主，无框透明面板）。
    private var scrollPreviewPanel: NSPanel?
    private var scrollPreviewView: LiveStitchPreviewView?
    /// 已捕获像素高累计（工具条计数用，帧高求和的近似值）。
    private var scrollCapturedPixelHeight = 0
    /// 滚轮事件监听（CGEventTap，listenOnly）：检测手动滚动、触发手动模式。
    private var scrollEventTap: CFMachPort?
    private var scrollEventTapSource: CFRunLoopSource?
    /// 截帧调度器：滚轮事件重置 0.08s 静止定时器 + 0.25s 强制截帧上限；
    /// 定时器经 DispatchWorkItem 在主队列实现（schedule/cancelScheduled 注入）。
    private var scrollScheduler: ScrollCaptureScheduler?
    private var scrollSchedulerWorkItem: DispatchWorkItem?
    /// 自动滚动器（三档速度）；滚动动作 = 发合成滚轮事件 + 喂给调度器统一截帧。
    private var scrollAutoScroller: ScrollAutoScroller?
    private var scrollScrollerWorkItem: DispatchWorkItem?
    /// 自动终止提示类型（预算触顶 / 滚动到底），完成时并入结果窗 issues。
    private var scrollAutoStopKind: ScrollResultIssueViewData.Kind?
    /// 收尾防重入标记（拼接中）。
    private var scrollFinishing = false
    /// 后台拼接结果代次：取消/重进时使旧的拼接回调失效。
    private var scrollResultGeneration = 0

    // MARK: 长截图状态（结果窗期）

    /// 结果窗强引用（展示后保持存活，各出口回调由本类处理）。
    private var scrollResultPanel: ScrollResultPanel?
    /// 结果窗当前展示图（保存/复制/贴图/编辑均以此为源，编辑后更新）。
    private var scrollResultImage: NSImage?
    /// 结果窗贴图定位点（会话数据仍在时预先算好）。
    private var scrollResultPinPoint: CGPoint = .zero
    /// 长图标注编辑器（同一编辑器复用，重复点击仅前置窗口）。
    private var scrollEditorWindow: ScrollImageEditorWindow?
    /// 结果窗展示期间的 ESC 关闭监听（会话 escMonitor 已随 finish 移除）。
    private var scrollResultEscMonitor: Any?
    /// L 键进入长截图（kVK_ANSI_L）。
    private static let lKeyCode: CGKeyCode = 37
    /// 预览缩略图目标宽度（像素）。
    private static let previewThumbnailWidthPx = 216

    /// 截图会话结束时回调（用于重置 ScreenshotSession 状态）。
    var onFinished: (() -> Void)?

    func start() {
        DiagLog.write("ScreenshotCoordinator.start()")

        // 0. 先清理可能残留的旧覆盖层（防止叠加变黑）
        cleanupExistingOverlays()

        // 1. 请求屏幕录制权限
        captureService.requestPermission()

        // 2. 捕获所有屏幕画面（在显示覆盖层之前）
        let displays = captureService.captureAllDisplays()
        // 无屏幕录制授权时 CGDisplayCreateImage 不报错，只会返回无窗口内容的壁纸图，
        // 记录预检结果便于从 diag.log 直接定位"截图变空桌面"类问题
        DiagLog.write("Captured \(displays.count) display(s), screenRecordingPreflight=\(CGPreflightScreenCaptureAccess())")
        guard !displays.isEmpty else { finish(); return }

        // 不切换 activationPolicy（App 固定 .regular，Dock 常驻）：覆盖层窗口自带
        // canJoinAllSpaces + fullScreenAuxiliary，在其他 App 全屏时也能于当前 Space 显示。
        NSApp.activate(ignoringOtherApps: true)

        // 4. 为每个屏幕创建覆盖层窗口
        overlayWindows = displays.compactMap { display -> ScreenshotOverlayWindow? in
            DiagLog.write("Display: id=\(display.displayID) frame=\(display.frame) imageSize=\(display.image.width)x\(display.image.height)")
            guard let screen = screenMatching(displayID: display.displayID, frame: display.frame) else {
                DiagLog.write("screenMatching returned nil for display \(display.displayID)")
                return nil
            }
            DiagLog.write("Matched screen: \(screen.frame)")
            let window = ScreenshotOverlayWindow(screen: screen, capturedImage: display.image)
            window.acceptsMouseMovedEvents = true
            let view = window.overlayView!
            view.onSelectionComplete = { [weak self, weak window] rect in
                self?.handleSelectionComplete(rect: rect, window: window)
            }
            view.onCancel = { [weak self] in self?.cancel() }
            // 悬停窗口检测（每屏一个）：detectWindowUnderMouse 实时取 NSEvent.mouseLocation，
            // 返回该屏视图坐标的窗口 rect
            view.hoverWindowProvider = { [weak self] in self?.detectWindowUnderMouse(on: screen) }
            // 鼠标活动重置空闲超时（选区未完成时才重新调度）
            view.onMouseActivity = { [weak self] in self?.resetIdleTimeout() }
            // 重选（编辑态框外点击）：开始时隐藏工具条；取消（未命中窗口恢复选区）时恢复工具条
            view.onReselectStarted = { [weak self] in self?.handleReselectStarted() }
            view.onReselectCancelled = { [weak self] in self?.handleReselectCancelled() }
            window.orderFrontRegardless()
            DiagLog.write("Window ordered front: frame=\(window.frame) level=\(window.level.rawValue)")
            return window
        }

        DiagLog.write("Created \(overlayWindows.count) overlay window(s)")

        // 仅将主显示器窗口设为 key，确保键盘事件和首次鼠标点击直达视图
        if let keyWindow = overlayWindows.first(where: { $0.screen == NSScreen.main }) ?? overlayWindows.first {
            keyWindow.makeKeyAndOrderFront(nil)
            keyWindow.makeFirstResponder(keyWindow.overlayView)
            DiagLog.write("Key window set: frame=\(keyWindow.frame)")
        }

       // 5. 安装 ESC 本地事件监听（不依赖 first responder）
       installEscMonitor()

       // 6. 自动检测鼠标下窗口区域作为初始选区
       autoDetectSelection()

       // 7. 空闲超时安全网：若覆盖层不可见（如全屏 Space 下），15 秒后自动清理
       scheduleIdleTimeout()
    }

    /// 启动/重置空闲超时定时器：距本次调度 15 秒内无任何鼠标活动且未完成选区时自动结束会话。
    /// 可重入：每次鼠标活动（mouseDown/mouseMoved/mouseDragged）都会重新调度。
    private func scheduleIdleTimeout() {
        idleTimeoutTimer?.invalidate()
        idleTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self = self, !self.overlayWindows.isEmpty else { return }
            // 防御：选区已完成（编辑态无超时语义）时不再强制结束
            guard self.selectionRect == nil else { return }
            DiagLog.write("Idle timeout: no mouse activity within 15s, finishing screenshot (overlay may not be visible)")
            self.finish()
        }
    }

    /// 鼠标活动重置空闲超时：仅在选区未完成时重新调度（选区完成后进入编辑态，无超时）。
    private func resetIdleTimeout() {
        guard selectionRect == nil else { return }
        scheduleIdleTimeout()
    }

    /// 取消空闲超时定时器（用户已开始操作）。
    private func cancelIdleTimeout() {
        idleTimeoutTimer?.invalidate()
        idleTimeoutTimer = nil
    }

    /// 自动检测鼠标所在屏幕下最顶层窗口的区域，作为初始选区。
    private func autoDetectSelection() {
        let mouseLocation = NSEvent.mouseLocation
        guard let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else { return }
        guard let overlay = overlayWindows.first(where: { $0.screen == mouseScreen }) else { return }
        guard let detected = detectWindowUnderMouse(on: mouseScreen) else { return }

        let view = overlay.overlayView!
        let clamped = SelectionRect.clamp(detected, to: view.bounds)
        guard SelectionRect.isValid(clamped, minimum: 10) else { return }
        view.selectionRect = clamped
        view.needsDisplay = true
        DiagLog.write("Auto-detected selection: \(clamped) on screen \(mouseScreen.frame)")
    }

    /// 通过 CGWindowList 检测鼠标下最顶层的普通窗口（排除自身），返回视图坐标矩形。
    private func detectWindowUnderMouse(on screen: NSScreen) -> CGRect? {
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        // CG 坐标原点在主屏左上，NSScreen 原点在左下，需翻转 y 轴
        let cgMouse = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourPid = ProcessInfo.processInfo.processIdentifier
        let windows: [WindowInfo] = windowList.compactMap { info in
            guard let boundsRef = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsRef),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int,
                  let windowId = info[kCGWindowNumber as String] as? Int else { return nil }
            return WindowInfo(bounds: bounds, layer: layer, ownerPid: Int32(pid), windowId: windowId)
        }

        guard let detected = WindowDetector.topmostWindow(
            at: cgMouse, in: windows, excludingPids: [ourPid]
        ) else { return nil }

        return ScreenCoordinateConverter.cgRectToViewRect(
            detected.bounds, screenFrame: screen.frame, primaryScreenHeight: primaryHeight
        )
    }

    /// 清理残留的旧覆盖层窗口（防止多次 F1 导致叠加变黑）。
    private func cleanupExistingOverlays() {
        if !overlayWindows.isEmpty {
            DiagLog.write("Cleaning up \(overlayWindows.count) existing overlay window(s)")
            for w in overlayWindows { w.orderOut(nil) }
            overlayWindows.removeAll()
        }
        toolbar?.closeAllPanels()
        toolbar?.orderOut(nil)
        toolbar = nil
        activeOverlay = nil
        selectionRect = nil
    }

    /// 安装 ESC 键本地监听：无论 first responder 是谁都能捕获 ESC。
    private func installEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == ScreenshotSession.escKeyCode {
                // 优先取消文字编辑；无文字编辑时才取消整个截图
                if self?.activeOverlay?.overlayView?.cancelTextEditingIfActive() == true {
                    return nil
                }
               DiagLog.write("ESC pressed via local monitor, cancelling screenshot")
               self?.cancel()
               return nil // 消费事件
           }
            // F3 = 贴图当前选区（本地监听备份，覆盖层为 key 窗口时可靠触发）
            if event.keyCode == ScreenshotHotkeyAction.f3KeyCode {
                DiagLog.write("F3 pressed via local monitor, pinning selection")
                self?.pinCurrentSelection()
                return nil
            }
            // L = 长截图（主工具条出现期间的快捷入口）：
            // 与 ESC 共用局部监听（随会话结束移除）；滚动模式中/无选区时忽略；
            // 文字编辑中（field editor 为 firstResponder）不劫持，事件照常传递
            if event.keyCode == ScreenshotCoordinator.lKeyCode,
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               self?.toolbar != nil,
               self?.scrollController == nil,
               self?.selectionRect != nil {
                if let responder = self?.activeOverlay?.firstResponder, responder is NSText {
                    return event
                }
                DiagLog.write("L pressed via local monitor, entering scroll capture")
                self?.toolbarDidScroll()
                return nil
            }
            return event
        }
        DiagLog.write("ESC + F3 + L local monitor installed")
    }

    // MARK: 选区完成

    private func handleSelectionComplete(rect: CGRect, window: ScreenshotOverlayWindow?) {
        guard let window = window else { return }
        // 幂等清理：重选成功（单击点选窗口）等场景再次进入时先移除旧工具条，避免双工具条
        toolbar?.closeAllPanels()
        toolbar?.orderOut(nil)
        toolbar = nil
        // 用户已开始操作，取消空闲超时
        cancelIdleTimeout()
        activeOverlay = window
        selectionRect = rect
        // 「重复上次区域」数据源：选区完成即记录（选区移动/缩放时随 onSelectionChanged 更新）
        recordLastRegion(rect: rect, screen: window.screen)
       window.overlayView!.isEditMode = true
        // 不自动选标注工具：默认光标模式，用户从工具条选择后才开始画标注
        window.overlayView!.currentTool = nil
        // 圆角用持久化的画布设置（跨会话一致），并夹取到选区尺寸上限，同步工具条按钮状态
        window.overlayView!.cornerRadius = CornerRounding.clampedRadius(
            canvasSettings.cornerRadius, for: rect.size)
        window.overlayView!.needsDisplay = true
        // 选区移动/缩放后同步协调器的 selectionRect，确保后续贴图/保存裁剪正确
       window.overlayView!.onSelectionChanged = { [weak self, weak window] newRect in
           self?.selectionRect = newRect
           self?.recordLastRegion(rect: newRect, screen: window?.screen)
       }
        // 标注变化时同步撤销按钮可用状态
        window.overlayView!.onAnnotationsChanged = { [weak self] in
            guard let view = self?.activeOverlay?.overlayView else { return }
            self?.toolbar?.updateUndoButton(canUndo: view.annotations.canUndo)
        }

        buildToolbar(for: window, rect: rect)

        for w in overlayWindows where w !== window {
            w.orderOut(nil)
        }
        // 不调用 window.makeKey()：那会把覆盖层提到最前面遮住工具条。
        // nonactivatingPanel 不抢 key，覆盖层从 start() 起即为 key，可正常接收鼠标事件。
        DiagLog.write("Edit mode ready: currentTool=nil, toolbar shown above overlay")
    }

    /// 创建并显示工具条（选区上方定位 + 圆角/阴影状态同步）。
    /// 选区完成与延时截图结束（恢复编辑态）共用。
    private func buildToolbar(for window: ScreenshotOverlayWindow, rect: CGRect) {
        let toolbar = ScreenshotToolbar()
        toolbar.toolbarDelegate = self
        let tbFrame = toolbar.frame
        let screen = window.screen ?? NSScreen.main!
        // 工具条定位在选区正上方（含屏幕 origin 偏移，支持多屏）
        let pos = ToolbarPositioner.position(
            forSelection: rect, toolbarSize: tbFrame.size, screenFrame: screen.frame
        )
        toolbar.setFrameOrigin(pos)
        // 工具条为 nonactivatingPanel，仅显示不抢占 key；保持覆盖层为 key 窗口，
        // 否则点击覆盖层时首击被窗口激活吞掉、无法绘制标注
        toolbar.orderFrontRegardless()
        self.toolbar = toolbar
        // 同步圆角按钮状态（默认已启用圆角）
        toolbar.updateCornerRadius(window.overlayView!.cornerRadius)
        // 同步阴影状态
        toolbar.updateCanvasShadowButton(enabled: canvasSettings.shadowEnabled)
        toolbar.updateCanvasShadowOpacity(canvasSettings.shadowOpacity)
    }

    // MARK: 重复上次区域（记录侧）

    /// 记录最近一次成功截图的选区（UserDefaults 持久化，「重复上次区域」由
    /// LastRegionRepeatController.repeatAndCopy() 读取，集成者在菜单栏菜单接线）。
    private func recordLastRegion(rect: CGRect, screen: NSScreen?) {
        guard let screen = screen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return }
        lastRegionStore.save(LastRegionRecord(
            rect: rect, displayID: displayID, screenPointSize: screen.frame.size))
    }

    // MARK: 重选（编辑态框外点击重新框选/点选窗口）

    /// 重选开始：隐藏工具条（保留引用，取消重选时直接恢复显示）。
    /// 重选成功走 handleSelectionComplete 重建工具条（开头有幂等清理，不会双工具条）。
    private func handleReselectStarted() {
        DiagLog.write("Reselect started: hiding toolbar")
        toolbar?.hideTooltips()
        toolbar?.closeAllPanels()
        toolbar?.orderOut(nil)
    }

    /// 重选取消（单击未命中窗口，覆盖层已恢复原选区并回到编辑态）：恢复工具条显示。
    private func handleReselectCancelled() {
        DiagLog.write("Reselect cancelled: restoring toolbar")
        toolbar?.orderFrontRegardless()
    }

    // MARK: 截取最终图片

    private func renderFinalImage() -> NSImage? {
        guard let sel = selectionRect, let cg = renderFinalCGImage() else { return nil }
        return NSImage(cgImage: cg, size: sel.size)
    }

    /// 渲染最终 CGImage（裁剪 + 标注合成），供贴图直接使用，避免 NSImage 转换丢精度。
    private func renderFinalCGImage() -> CGImage? {
        guard let overlay = activeOverlay, let sel = selectionRect else { return nil }
        let view = overlay.overlayView!
        let image = view.capturedImage
        // 选区为视图点坐标(左下原点)，CGImage 原点在左上，需翻转 y 轴后裁剪
        let cropRect = SelectionRect.cropRectPixels(selection:
            sel, imageSize: CGSize(width: image.width, height: image.height),
            viewSize: view.bounds.size
        )
      guard let cropped = image.cropping(to: cropRect) else { return nil }
       DiagLog.write("renderFinalImage: full=\(image.width)x\(image.height) cropRect=\(cropRect) cropped=\(cropped.width)x\(cropped.height) selPts=\(sel.size) annotations=\(view.annotations.count)")

       var finalImage: CGImage
        if view.annotations.count > 0 || view.drawingAnnotation != nil {
           finalImage = compositeAnnotations(on: cropped, from: overlay) ?? cropped
        } else {
            finalImage = cropped
        }

        // 应用圆角蒙版（半径 > 0 时裁剪为圆角，四角透明）
        let ptRadius = CornerRounding.clampedRadius(view.cornerRadius, for: sel.size)
        if ptRadius > 0 {
            let scaleX = view.bounds.width > 0 ? CGFloat(cropped.width) / view.bounds.width : 1
            let pxRadius = ptRadius * scaleX
            if let rounded = ScreenshotImagePipeline.applyRoundedCorners(to: finalImage, radius: pxRadius) {
                finalImage = rounded
            }
        }
        // 应用阴影边框（画布设置中阴影开启时，在边缘描深色线，不改变图片尺寸）
        if canvasSettings.shadowEnabled {
            let scaleX = view.bounds.width > 0 ? CGFloat(cropped.width) / view.bounds.width : 1
            let pxRadius = CornerRounding.clampedRadius(view.cornerRadius, for: sel.size) * scaleX
            if let bordered = ScreenshotImagePipeline.applyShadowBorder(to: finalImage, cornerRadius: pxRadius,
                                                                        opacity: canvasSettings.shadowOpacity) {
                finalImage = bordered
            }
        }
        return finalImage
    }

    private func compositeAnnotations(on cropped: CGImage, from overlay: ScreenshotOverlayWindow) -> CGImage? {
        let width = cropped.width
        let height = cropped.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 标准上下文（原点左下），直接绘制裁剪后的图片即正立
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 按 Retina 缩放比缩放 CTM，使标注点坐标（视图点）映射到像素
        let view = overlay.overlayView!
        let viewSize = view.bounds.size
        let scaleX = viewSize.width > 0 ? CGFloat(view.capturedImage.width) / viewSize.width : 1
        let scaleY = viewSize.height > 0 ? CGFloat(view.capturedImage.height) / viewSize.height : 1
        ctx.scaleBy(x: scaleX, y: scaleY)

        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = nsContext
        for annotation in view.annotations.annotations {
            view.drawAnnotationPublic(annotation, in: ctx)
        }
        NSGraphicsContext.current = nil
        return ctx.makeImage()
    }

    // MARK: 操作

    @discardableResult
    private func copyToClipboard() -> Bool {
        guard let image = renderFinalImage() else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        let ok = pb.writeObjects([image])
        if ok { feedback.showCopied() }
        return ok
    }

    private func saveToFile() {
        guard let image = renderFinalImage() else { return }
        // 统一保存服务：目录创建/查重命名/编码/写盘全链路 do-catch，
        // 失败弹错误提示 + DiagLog（修复旧实现保存失败静默丢失），成功 Finder 定位 + toast
        saveService.save(image: image, config: .init())
    }

    private func pinToDesktop() {
        guard let sel = selectionRect, let cgImage = renderFinalCGImage() else { return }
        let screen = activeOverlay?.screen ?? NSScreen.main!
        let pinPoint = PinPositioner.pinPoint(selectionOrigin: sel.origin, screenFrame: screen.frame)
        DiagLog.write("pinToDesktop: sel=\(sel) screen=\(screen.frame) pinPoint=\(pinPoint)")
        // 与 renderFinalCGImage 相同口径的圆角半径（点），供呼吸灯贴合贴图圆角
        let ptRadius: CGFloat
        if let view = activeOverlay?.overlayView {
            ptRadius = CornerRounding.clampedRadius(view.cornerRadius, for: sel.size)
        } else {
            ptRadius = 0
        }
        let pin = PinWindow(cgImage: cgImage, displaySize: sel.size, at: pinPoint,
                            cornerRadius: ptRadius)
        pin.onClose = { [weak self, weak pin] in
            guard let pin = pin else { return }
            self?.pinWindows.removeAll { $0 === pin }
        }
        pin.makeKeyAndOrderFront(nil)
        pinWindows.append(pin)
    }

    /// 贴图当前选区并结束截图会话（F3 触发）。无选区时为空操作。
    func pinCurrentSelection() {
        guard selectionRect != nil else {
            DiagLog.write("pinCurrentSelection: no selection, ignoring")
            return
        }
        pinToDesktop()
        finish()
    }

    /// 结束截图会话：关闭所有覆盖层窗口、工具条，移除事件监听，恢复 App 策略。
    /// - Parameter cleanupScroll: 默认 true 全量清理长截图资源（含结果窗/controller）；
    ///   长截图拼接完成展示结果窗后传 false，保留 controller 与结果窗供各出口使用。
    func finish(cleanupScroll: Bool = true) {
        if cleanupScroll {
            cleanupScrollCapture()
        }
        cancelIdleTimeout()
        // 延时截图资源：取消倒计时、移除浮窗与 Toast（ESC 取消延时也走此路径）
        delayCountdown?.cancel()
        delayCountdown = nil
        delayCaptureWorkItem?.cancel()
        delayCaptureWorkItem = nil
        countdownWindow?.orderOut(nil)
        countdownWindow = nil
        dismissToast()
        for w in overlayWindows { w.orderOut(nil) }
        toolbar?.closeAllPanels()
        toolbar?.orderOut(nil)
        overlayWindows.removeAll()
        toolbar = nil
        activeOverlay = nil
        selectionRect = nil

        if let escMonitor = escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }

        DiagLog.write("Screenshot finished")
        onFinished?()
    }

    func cancel() {
        DiagLog.write("Screenshot cancelled")
        finish()
    }

    // MARK: 辅助

    private func screenMatching(displayID: CGDirectDisplayID, frame: CGRect) -> NSScreen? {
        for screen in NSScreen.screens {
            let sid = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if sid == displayID { return screen }
        }
        return NSScreen.screens.first
    }
}

// MARK: - ScreenshotToolbarDelegate

extension ScreenshotCoordinator: ScreenshotToolbarDelegate {

    func toolbarDidSelect(tool: AnnotationType?) {
        DiagLog.write("toolbarDidSelect: tool=\(String(describing: tool)) activeOverlay=\(activeOverlay != nil)")
        activeOverlay?.overlayView!.currentTool = tool
        // 序号标注复位语义：每次重新选中该工具，序号从 1 重新开始
        if tool == .counter {
            activeOverlay?.overlayView!.annotations.resetCounter()
        }
    }

    func toolbarDidSelectColor(_ color: AnnotationColor) {
        DiagLog.write("toolbarDidSelectColor: color=\(color) activeOverlay=\(activeOverlay != nil)")
        activeOverlay?.overlayView!.currentColor = color
        // 未选工具时点颜色，默认矩形工具，使「点红色即可画红框」
        if let view = activeOverlay?.overlayView, view.currentTool == nil {
            let tool = AnnotationModel.defaultTool(whenColorSelected: view.currentTool)
            view.currentTool = tool
            toolbar?.selectTool(tool)
            DiagLog.write("toolbarDidSelectColor: auto-selected tool=\(String(describing: tool))")
        }
    }

    func toolbarDidToggleCornerRadius() {
        guard let view = activeOverlay?.overlayView, let sel = selectionRect else { return }
        canvasSettings = canvasSettings.withNextCornerRadius(selectionSize: sel.size)
        view.cornerRadius = canvasSettings.cornerRadius
        toolbar?.updateCornerRadius(view.cornerRadius)
        view.needsDisplay = true
        DiagLog.write("toolbarDidToggleCornerRadius: radius=\(view.cornerRadius)")
    }

    func toolbarDidToggleShadow() {
        canvasSettings = canvasSettings.toggledShadow()
        toolbar?.updateCanvasShadowButton(enabled: canvasSettings.shadowEnabled)
        DiagLog.write("toolbarDidToggleShadow: enabled=\(canvasSettings.shadowEnabled)")
    }

    func toolbarDidSetShadowOpacity(_ opacity: CGFloat) {
        canvasSettings = canvasSettings.withShadowOpacity(opacity)
        toolbar?.updateCanvasShadowOpacity(canvasSettings.shadowOpacity)
        DiagLog.write("toolbarDidSetShadowOpacity: opacity=\(opacity)")
    }

    /// 从预捕获帧裁出选区像素图（OCR 等共用）。
    private func croppedSelectionImage(overlay: ScreenshotOverlayWindow, selection: CGRect) -> CGImage? {
        let view = overlay.overlayView!
        let image = view.capturedImage
        let cropRect = SelectionRect.cropRectPixels(
            selection: selection, imageSize: CGSize(width: image.width, height: image.height),
            viewSize: view.bounds.size
        )
        return image.cropping(to: cropRect)
    }

    /// 共用 OCR 执行：Vision accurate 文字识别 + CoreImage 二维码检测（同图同后台队列），
    /// 完成回主线程。文字与二维码分别交付，互不依赖。
    private func runOCR(on image: CGImage,
                        completion: @escaping (_ text: String, _ qrCodes: [String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = Self.recognizeText(in: image) ?? ""
            let qrCodes = QRCodeDetector.detect(in: image)
            DiagLog.write("runOCR: text=\(text.isEmpty ? "empty" : "\(text.count) chars") qrcodes=\(qrCodes.count)")
            DispatchQueue.main.async { completion(text, qrCodes) }
        }
    }

    /// Vision 文字识别（同步，须在后台队列调用）。失败返回 nil（与空文本区分）。
    private static func recognizeText(in image: CGImage) -> String? {
        var result: String?
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            let items = observations.compactMap { obs -> OCRTextItem? in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                return OCRTextItem(text: candidate.string, confidence: candidate.confidence,
                                   boundingBox: obs.boundingBox)
            }
            let filtered = OCRTextSorter.filterByConfidence(items)
            result = OCRTextSorter.toText(filtered)
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image)
        try? handler.perform([request])
        return result
    }

    func toolbarDidRequestOCR() {
        guard let overlay = activeOverlay, let sel = selectionRect,
              let cropped = croppedSelectionImage(overlay: overlay, selection: sel) else { return }
        DiagLog.write("toolbarDidRequestOCR: starting OCR on \(cropped.width)x\(cropped.height) image")
        runOCR(on: cropped) { [weak self] text, qrCodes in
            self?.showOCRResult(text: text, qrCodes: qrCodes)
        }
    }

    /// 静默 OCR：「识字并复制」直达路径——不弹结果面板，识别结果直接写剪贴板 + Toast。
    /// 仅二维码无文字时复制二维码内容；两者皆无时提示未识别到内容。
    func toolbarDidRequestOCRAndCopy() {
        guard let overlay = activeOverlay, let sel = selectionRect,
              let cropped = croppedSelectionImage(overlay: overlay, selection: sel) else { return }
        runOCR(on: cropped) { [weak self] text, qrCodes in
            guard let self = self else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            if !text.isEmpty {
                if pb.setString(text, forType: .string) {
                    self.showToast("已复制 \(text.count) 字")
                }
            } else if let qr = qrCodes.first {
                if pb.setString(qr, forType: .string) {
                    self.showToast("已复制二维码：\(QRCodeDetector.summary(of: qr))")
                }
            } else {
                self.showToast("未识别到内容")
            }
        }
    }

    /// 显示 OCR 识别结果面板（可编辑 + 复制；检出二维码时顶部加「二维码内容」区块）。
    private func showOCRResult(text: String, qrCodes: [String] = []) {
        ocrResultPanel?.orderOut(nil)
        let hasQR = !qrCodes.isEmpty
        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = hasQR ? 396 : 300
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered, defer: false)
        panel.title = "识别结果"
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: panel.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content

        // 二维码区块（仅命中时创建）：标题 + 可选中内容 + 复制按钮
        var qrBottomAnchor: NSLayoutYAxisAnchor = content.topAnchor
        if hasQR {
            let qrContainer = NSView()
            qrContainer.wantsLayer = true
            qrContainer.layer?.borderWidth = 1
            qrContainer.layer?.borderColor = NSColor.separatorColor.cgColor
            qrContainer.layer?.cornerRadius = 6
            qrContainer.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(qrContainer)

            let qrTitle = NSTextField(labelWithString: "二维码内容")
            qrTitle.font = .systemFont(ofSize: 11, weight: .semibold)
            qrTitle.textColor = .secondaryLabelColor
            qrTitle.translatesAutoresizingMaskIntoConstraints = false
            qrContainer.addSubview(qrTitle)

            let qrTextView = NSTextView()
            qrTextView.isEditable = false
            qrTextView.isSelectable = true
            qrTextView.font = .systemFont(ofSize: 13)
            qrTextView.string = qrCodes.joined(separator: "\n")
            let qrScroll = NSScrollView()
            qrScroll.translatesAutoresizingMaskIntoConstraints = false
            qrScroll.hasVerticalScroller = true
            qrScroll.borderType = .noBorder
            qrScroll.documentView = qrTextView
            qrContainer.addSubview(qrScroll)

            let qrCopyBtn = NSButton(title: "复制", target: self, action: #selector(copyQRText(_:)))
            qrCopyBtn.translatesAutoresizingMaskIntoConstraints = false
            qrCopyBtn.bezelStyle = .rounded
            qrContainer.addSubview(qrCopyBtn)

            NSLayoutConstraint.activate([
                qrContainer.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
                qrContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
                qrContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                qrContainer.heightAnchor.constraint(equalToConstant: 96),
                qrTitle.topAnchor.constraint(equalTo: qrContainer.topAnchor, constant: 6),
                qrTitle.leadingAnchor.constraint(equalTo: qrContainer.leadingAnchor, constant: 8),
                qrCopyBtn.centerYAnchor.constraint(equalTo: qrTitle.centerYAnchor),
                qrCopyBtn.trailingAnchor.constraint(equalTo: qrContainer.trailingAnchor, constant: -8),
                qrScroll.topAnchor.constraint(equalTo: qrTitle.bottomAnchor, constant: 4),
                qrScroll.leadingAnchor.constraint(equalTo: qrContainer.leadingAnchor, constant: 8),
                qrScroll.trailingAnchor.constraint(equalTo: qrContainer.trailingAnchor, constant: -8),
                qrScroll.bottomAnchor.constraint(equalTo: qrContainer.bottomAnchor, constant: -6),
            ])
            ocrQRTextView = qrTextView
            qrBottomAnchor = qrContainer.bottomAnchor
        } else {
            ocrQRTextView = nil
        }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView()
        textView.isEditable = true
        textView.font = .systemFont(ofSize: 13)
        textView.string = text.isEmpty ? "（未识别到文字）" : text
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 6, height: 6)
        scrollView.documentView = textView
        content.addSubview(scrollView)

        let copyBtn = NSButton(title: "复制", target: self, action: #selector(copyOCRText(_:)))
        copyBtn.translatesAutoresizingMaskIntoConstraints = false
        copyBtn.bezelStyle = .rounded
        copyBtn.keyEquivalent = "\r"
        content.addSubview(copyBtn)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: qrBottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: copyBtn.topAnchor, constant: -12),
            copyBtn.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            copyBtn.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
        ])

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        ocrResultPanel = panel
        ocrTextView = textView
    }

    /// 复制二维码区块内容并关闭面板。
    @objc private func copyQRText(_ sender: NSButton) {
        guard let qrTextView = ocrQRTextView else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(qrTextView.string, forType: .string)
        DiagLog.write("OCR QR content copied to pasteboard")
        ocrResultPanel?.orderOut(nil)
        ocrResultPanel = nil
    }

    @objc private func copyOCRText(_ sender: NSButton) {
        guard let textView = ocrTextView else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(textView.string, forType: .string)
        DiagLog.write("OCR text copied to pasteboard")
        ocrResultPanel?.orderOut(nil)
        ocrResultPanel = nil
    }

    func toolbarDidUndo() {
        guard let view = activeOverlay?.overlayView else { return }
        view.annotations.undo()
        view.needsDisplay = true
        toolbar?.updateUndoButton(canUndo: view.annotations.canUndo)
        DiagLog.write("toolbarDidUndo: remaining=\(view.annotations.count)")
    }

    func toolbarDidCopy() { copyToClipboard(); finish() }
    func toolbarDidSave() { saveToFile(); finish() }
    func toolbarDidPin() { pinToDesktop(); finish() }
    func toolbarDidCancel() { cancel() }

    // MARK: - 延时截图

    /// 延时截图：隐藏覆盖层与工具条 → 全屏透明浮窗大号倒计时（每秒 beep）→
    /// 归零移除浮窗、抓「选区所在屏」新鲜帧替换预捕获底图 → 恢复编辑态（选区/标注/工具全保留）。
    /// 期间 ESC 经既有会话监听触发 cancel() → finish() 统一清理倒计时。
    func toolbarDidRequestDelay(seconds: Int) {
        guard let overlay = activeOverlay, selectionRect != nil, delayCountdown == nil else { return }
        let screen = overlay.screen ?? NSScreen.main!
        // 隐藏全部截图 UI（悬停提示一并收起）
        toolbar?.hideTooltips()
        toolbar?.closeAllPanels()
        toolbar?.orderOut(nil)
        for w in overlayWindows { w.orderOut(nil) }

        // 倒计时浮窗（选区所在屏，数字优先取选区中央）
        let win = ScreenshotCountdownWindow(screen: screen, focusRect: selectionRect)
        win.showCountdown(seconds: seconds)
        countdownWindow = win

        // 倒计时状态机（调度注入主队列，可单测的纯逻辑在 DelayCaptureCountdown）
        let countdown = DelayCaptureCountdown(
            seconds: seconds,
            schedule: { [weak self] delay, fire in
                guard let self = self else { return }
                let item = DispatchWorkItem(block: fire)
                self.delayCaptureWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            },
            cancelScheduled: { [weak self] in
                self?.delayCaptureWorkItem?.cancel()
                self?.delayCaptureWorkItem = nil
            })
        countdown.onTick = { [weak win] remaining in
            NSSound.beep()
            win?.update(number: remaining)
        }
        countdown.onFinish = { [weak self] in self?.handleDelayCaptureFinished() }
        countdown.start()
        delayCountdown = countdown
        DiagLog.write("Delay capture started: \(seconds)s")
    }

    /// 倒计时结束：移除浮窗 → 抓选区所在屏新鲜帧（不是会话开始时的预捕获旧图）→
    /// 恢复覆盖层与工具条进入编辑模式。
    private func handleDelayCaptureFinished() {
        delayCountdown = nil
        countdownWindow?.orderOut(nil)
        countdownWindow = nil
        guard let overlay = activeOverlay, let sel = selectionRect else {
            finish()
            return
        }
        // 先移除浮窗再抓帧，保证倒计时数字不被截进画面
        let screen = overlay.screen ?? NSScreen.main!
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
            ?? CGMainDisplayID()
        if let fresh = freshFrames.capture(displayID) {
            overlay.overlayView!.capturedImage = fresh
        } else {
            DiagLog.write("Delay capture: fresh frame capture failed, keep pre-captured frame")
        }
        overlay.orderFrontRegardless()
        overlay.overlayView!.isEditMode = true
        overlay.overlayView!.needsDisplay = true
        // 恢复编辑态工具条（与选区完成共用构建；不重置 currentTool/标注，延时前画的序号继续递增）
        buildToolbar(for: overlay, rect: sel)
        DiagLog.write("Delay capture finished: fresh frame applied, edit mode restored")
    }

    // MARK: - 轻量 Toast（自定义文案）

    /// 毛玻璃轻 Toast：静默 OCR「已复制 N 字」等自定义文案场景（固定文案用 feedback）。
    private func showToast(_ text: String) {
        toastHideWorkItem?.cancel()
        toastPanel?.orderOut(nil)
        toastGeneration += 1
        let generation = toastGeneration

        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let panelWidth = min(460, 14 + 18 + 7 + textWidth + 14)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 44),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.hidesOnDeactivate = false

        let visual = NSVisualEffectView()
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 14
        visual.layer?.masksToBounds = true
        visual.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = visual

        let icon = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill",
                                              accessibilityDescription: text) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(icon)

        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: visual.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: visual.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: visual.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: visual.trailingAnchor, constant: -14),
        ])

        // 主屏菜单栏下方居中（对齐 ScreenshotFeedbackPresenter）
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panelWidth / 2,
                y: visible.maxY - panel.frame.height - 8))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        toastPanel = panel

        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.toastGeneration == generation else { return }
            self.toastPanel?.orderOut(nil)
            self.toastPanel = nil
        }
        toastHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 + 1.6, execute: item)
    }

    /// 关闭自定义 Toast（会话结束时调用，防止残留）。
    private func dismissToast() {
        toastHideWorkItem?.cancel()
        toastHideWorkItem = nil
        toastPanel?.orderOut(nil)
        toastPanel = nil
        toastGeneration += 1
    }

    // MARK: - 长截图入口（v2）

    /// 进入长截图：建 controller（截帧排除边框窗口）/ scheduler / scroller，
    /// 隐藏主工具条与覆盖层，显示边框 + 控制工具条 + 实时预览；
    /// 等待鼠标滚轮（手动模式）或工具条开始按钮（自动模式）。
    func toolbarDidScroll() {
        guard let overlay = activeOverlay, let sel = selectionRect, scrollController == nil else { return }
        let screen = overlay.screen ?? NSScreen.main!
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        let captureRect = ScrollCaptureSession.displayCaptureRect(viewRect: sel, screenHeight: screen.frame.height)
        let scaleFactor = screen.backingScaleFactor

        // 隐藏主工具条与全部覆盖层（悬停提示一并收起）
        toolbar?.hideTooltips()
        toolbar?.closeAllPanels()
        toolbar?.orderOut(nil)
        for w in overlayWindows { w.orderOut(nil) }

        // 先建边框窗口：截帧以它的 windowNumber 为排除锚点（v2 契约构造器一次性传入）
        let border = showScrollBorder(sel: sel, screen: screen)
        scrollBorderWindow = border
        let excludeID = border.windowNumber > 0 ? CGWindowID(border.windowNumber) : nil
        let controller = ScrollCaptureController(
            captureRect: captureRect, displayID: displayID,
            excludeWindowID: excludeID, scaleFactor: scaleFactor)
        scrollController = controller

        // 截帧调度器：静止 0.08s 截帧 + 0.25s 强制上限（防惯性滚动饿死），
        // 定时器经 DispatchWorkItem 注册到主队列
        let scheduler = ScrollCaptureScheduler(
            schedule: { [weak self] delay, fire in
                guard let self = self else { return }
                let item = DispatchWorkItem(block: fire)
                self.scrollSchedulerWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            },
            cancelScheduled: { [weak self] in
                self?.scrollSchedulerWorkItem?.cancel()
                self?.scrollSchedulerWorkItem = nil
            })
        scheduler.onCaptureNeeded = { [weak self] in self?.onSchedulerCaptureNeeded() }
        scrollScheduler = scheduler

        // 自动滚动器：滚动动作 = 发送合成滚轮事件（负值 = 向下）+ 喂给调度器统一截帧节奏
        let scroller = ScrollAutoScroller(
            schedule: { [weak self] interval, fire in
                guard let self = self else { return }
                let item = DispatchWorkItem(block: fire)
                self.scrollScrollerWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
            },
            cancelScheduled: { [weak self] in
                self?.scrollScrollerWorkItem?.cancel()
                self?.scrollScrollerWorkItem = nil
            },
            scroll: { [weak self] pixels in
                self?.performAutoScrollTick(pixels: pixels)
            })
        scrollAutoScroller = scroller

        // 控制工具条（默认慢速档）+ 实时生长预览条
        let scrollToolbar = ScrollCaptureToolbar()
        scrollToolbar.toolbarDelegate = self
        scrollToolbar.show(relativeTo: sel, on: screen)
        scrollToolbar.setSpeed(.slow)
        self.scrollToolbar = scrollToolbar
        showScrollPreview(toolbar: scrollToolbar)

        // 启动滚轮事件监听：鼠标滚动自动触发手动模式
        startScrollEventMonitor()
        DiagLog.write("Scroll capture ready(v2): sel=\(sel) captureRect=\(captureRect) scale=\(scaleFactor) exclude=\(String(describing: excludeID))")
    }

    // MARK: - 滚轮事件监听（手动模式）

    private func startScrollEventMonitor() {
        let eventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let coordinator = Unmanaged<ScreenshotCoordinator>.fromOpaque(refcon).takeUnretainedValue()
                coordinator.onScrollEventDetected()
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DiagLog.write("Scroll event tap creation failed (accessibility?)")
            return
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        scrollEventTap = tap
        scrollEventTapSource = runLoopSource
        DiagLog.write("Scroll event monitor started")
    }

    /// 移除滚轮事件监听（disable tap + 移除 run loop source，防止多次进入滚动模式累积泄漏）。
    private func removeScrollEventTap() {
        if let tap = scrollEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            scrollEventTap = nil
        }
        if let source = scrollEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            scrollEventTapSource = nil
        }
    }

    /// 滚轮事件回调（真实滚轮与自动模式的合成事件都会到达）：
    /// ready 状态下转入手动模式并立即同步截首帧（修首帧缺失）；
    /// 手动采集中把事件喂给调度器；自动运行中 tick 已喂给调度器，此处忽略避免双份。
    private func onScrollEventDetected() {
        guard let controller = scrollController, !scrollFinishing else { return }
        if controller.state == .ready {
            controller.startManual()
            let added = controller.captureFrame()
            if added { handleFrameAdded() }
            scrollScheduler?.scrollActivityOccurred()
            DiagLog.write("Scroll capture: manual mode started, firstFrameAdded=\(added)")
            return
        }
        guard scrollAutoScroller?.isRunning != true else { return }
        if controller.state == .capturing {
            scrollScheduler?.scrollActivityOccurred()
        }
    }

    // MARK: - 截帧调度（手动/自动统一路径）

    /// 调度器到期（静止 0.08s / 强制 0.25s）：截帧 → 刷新预览与计数 → 检查自动终止。
    private func onSchedulerCaptureNeeded() {
        guard let controller = scrollController, !scrollFinishing, controller.state == .capturing else { return }
        let added = controller.captureFrame()
        // 实际截帧已完成，无论入库成败都重置 maxDelay 基准（调度器契约）
        scrollScheduler?.captureDidPerform()
        if added { handleFrameAdded() }
        checkAutoStop()
    }

    /// 新帧入库：追加预览缩略图（自底向上生长）并同步工具条计数。
    private func handleFrameAdded() {
        guard let controller = scrollController, let frame = controller.lastFrame else { return }
        scrollCapturedPixelHeight += frame.height
        if let view = scrollPreviewView,
           let thumb = LiveStitchPreviewView.downsampledThumbnail(
                from: frame, targetWidthPx: ScreenshotCoordinator.previewThumbnailWidthPx) {
            view.append(pixelHeight: frame.height, thumbnail: thumb)
        }
        scrollToolbar?.updateCounter(frames: controller.frameCount, pixelHeight: scrollCapturedPixelHeight)
    }

    /// 每帧后检查会话自动终止（内存预算触顶 / auto 滚动到底）：记录提示并自动完成。
    private func checkAutoStop() {
        guard let controller = scrollController, controller.isDone, !scrollFinishing else { return }
        switch controller.stopReason {
        case .budgetReached: scrollAutoStopKind = .budgetReached
        case .bottomReached: scrollAutoStopKind = .autoBottom
        default: break
        }
        DiagLog.write("Scroll capture: session auto-finished, reason=\(controller.stopReasonText)")
        finishScrollCapture()
    }

    // MARK: - 自动滚动

    /// 自动滚动一拍：发送合成滚轮事件（负 delta = 向下滚动，内容上移、新内容出现在底部），
    /// 并把 tick 喂给调度器统一截帧节奏（手动/自动共用同一套静止检测 + 强制上限）。
    private func performAutoScrollTick(pixels: Int) {
        guard let controller = scrollController, controller.state == .capturing, !scrollFinishing else { return }
        let delta = Int32(-pixels)
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                            wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)
        scrollScheduler?.scrollActivityOccurred()
    }

    // MARK: - ScrollCaptureToolbarDelegate

    /// 开始/停止按钮：未运行则启动自动滚动（ready 先转 auto 并截首帧），
    /// 运行中则停止（保持采集中，可继续手动滚动或再次开启）。
    func scrollToolbarDidToggleRun(_ toolbar: ScrollCaptureToolbar) {
        guard let controller = scrollController, let scroller = scrollAutoScroller, !scrollFinishing else { return }
        if scroller.isRunning {
            scroller.stop()
            toolbar.setRunning(false)
            DiagLog.write("Scroll capture: auto scroll stopped (toggle off)")
            return
        }
        if controller.state == .ready {
            controller.startAuto()
            let added = controller.captureFrame()
            if added { handleFrameAdded() }
            scrollScheduler?.captureDidPerform()
            DiagLog.write("Scroll capture: auto mode started, speed=\(toolbar.currentSpeed) firstFrameAdded=\(added)")
        }
        guard controller.state == .capturing else { return }
        scroller.start(level: toolbar.currentSpeed)
        toolbar.setRunning(true)
    }

    /// 速度档位切换（工具条已自行更新按钮显示，这里同步滚动器节奏）。
    func scrollToolbarDidSelectSpeed(_ toolbar: ScrollCaptureToolbar, level: ScrollAutoSpeedLevel) {
        scrollAutoScroller?.changeSpeed(level)
        DiagLog.write("Scroll capture: speed changed to \(level)")
    }

    /// 完成按钮：停止采集、拼接并弹结果窗。
    func scrollToolbarDidFinish(_ toolbar: ScrollCaptureToolbar) {
        finishScrollCapture()
    }

    /// 取消按钮：放弃本次长截图并结束会话。
    func scrollToolbarDidCancel(_ toolbar: ScrollCaptureToolbar) {
        DiagLog.write("Scroll capture cancelled by user")
        finish()
    }

    // MARK: - 完成 & 清理

    /// 收尾（工具条完成按钮或自动终止触发）：
    /// 末帧补拍 → 停止输入 → 收采集 UI → 后台拼接 → 主线程弹结果窗。
    private func finishScrollCapture() {
        guard let controller = scrollController, !scrollFinishing else { return }
        scrollFinishing = true
        scrollResultGeneration += 1
        let generation = scrollResultGeneration
        DiagLog.write("Scroll capture finishing: frames=\(controller.frameCount) stopReason=\(controller.stopReasonText) budget=\(controller.reachedBudgetLimit)")

        // 末帧补拍：调度器尚有未触发的静止定时器时，先同步补拍最后一帧再取消
        //（captureFrame 在 stop 之前执行，session 仍为 capturing，补拍结果可入库）
        if scrollScheduler?.isPending == true {
            let added = controller.captureFrame()
            scrollScheduler?.cancelPending()
            DiagLog.write("Scroll capture: pending final capture flushed, added=\(added)")
        }
        scrollAutoScroller?.stop()
        controller.stop()
        DiagLog.write("Scroll capture stopped: reason=\(controller.stopReasonText)")

        // 结果窗的贴图定位必须在会话数据仍在时先算好（finish 后 selectionRect 置空）
        let pinScreen = activeOverlay?.screen ?? NSScreen.main!
        scrollResultPinPoint = PinPositioner.pinPoint(selectionOrigin: selectionRect?.origin ?? .zero,
                                                      screenFrame: pinScreen.frame)

        // 收采集期 UI 与输入（controller 保留：结果窗「强制重拼」仍需帧数据）
        scrollToolbar?.orderOut(nil)
        scrollToolbar = nil
        scrollPreviewPanel?.orderOut(nil)
        scrollPreviewPanel = nil
        scrollPreviewView = nil
        scrollBorderWindow?.orderOut(nil)
        scrollBorderWindow = nil
        removeScrollEventTap()
        scrollScheduler = nil
        scrollSchedulerWorkItem?.cancel()
        scrollSchedulerWorkItem = nil
        scrollAutoScroller = nil
        scrollScrollerWorkItem?.cancel()
        scrollScrollerWorkItem = nil

        // 拼接移到后台队列，完成后回主线程。
        // 强引用局部 controller：拼接期间即使会话被取消、scrollController 置空，
        // 拼接仍安全完成，结果由代次校验决定是否丢弃。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = controller.stitch()
            DispatchQueue.main.async { [weak self] in
                self?.completeScrollCapture(outcome: outcome, generation: generation)
            }
        }
    }

    /// 拼接完成（主线程）：成功弹结果窗（issues 桥接质量提示），失败给反馈并结束会话。
    private func completeScrollCapture(outcome: ScrollStitchOutcome, generation: Int) {
        // 会话已被取消/重进时丢弃过期结果
        guard generation == scrollResultGeneration, scrollFinishing else { return }
        scrollFinishing = false

        guard let controller = scrollController, let cgImage = outcome.image else {
            DiagLog.write("Scroll capture failed: stitch image nil (0 帧或全部边界失败)")
            feedback.showCaptureFailed(message: "长截图失败：未捕获到内容")
            finish()
            return
        }
        let image = controller.renderImage(cgImage)

        // issues 桥接：ScrollStitchIssue / Failure → 结果窗展示模型（含固定带与外推/丢帧）
        var issues: [ScrollResultIssueViewData] = []
        for issue in outcome.issues {
            switch issue {
            case .noReliableOverlap(let index):
                issues.append(.make(kind: .noReliableOverlap, frameIndex: index))
            case .ambiguousPattern(let index):
                issues.append(.make(kind: .ambiguousPattern, frameIndex: index))
            case .fixedBandExcluded(let height):
                issues.append(.make(kind: .fixedBandExcluded, bandHeight: height))
            }
        }
        for failure in outcome.failures {
            issues.append(.makeFailure(frameIndex: failure.frameIndex,
                                       extrapolated: failure.kind == .extrapolated,
                                       usedOffset: failure.usedOffset))
        }
        // 自动终止提示（预算触顶 / 滚动到底）
        if let autoStopKind = scrollAutoStopKind {
            issues.append(.make(kind: autoStopKind))
            scrollAutoStopKind = nil
        }

        scrollResultImage = image
        let panel = scrollResultPanel ?? ScrollResultPanel()
        scrollResultPanel = panel
        panel.show(image: image, issues: issues,
                   canRetryForced: outcome.requiresAttention, delegate: self)
        installResultEscMonitor()
        // 结束截图会话但保留 controller/结果窗（结果窗各出口仍需帧数据与图片）
        finish(cleanupScroll: false)
    }

    /// 长截图全量清理：采集期资源 + 结果窗阶段资源（取消/新会话开始时调用）。
    private func cleanupScrollCapture() {
        scrollScheduler = nil
        scrollSchedulerWorkItem?.cancel()
        scrollSchedulerWorkItem = nil
        scrollAutoScroller = nil
        scrollScrollerWorkItem?.cancel()
        scrollScrollerWorkItem = nil
        removeScrollEventTap()
        scrollToolbar?.orderOut(nil)
        scrollToolbar = nil
        scrollPreviewPanel?.orderOut(nil)
        scrollPreviewPanel = nil
        scrollPreviewView = nil
        scrollBorderWindow?.orderOut(nil)
        scrollBorderWindow = nil
        scrollCapturedPixelHeight = 0
        scrollAutoStopKind = nil
        scrollFinishing = false
        scrollResultGeneration += 1
        dismissScrollResult()
    }

    /// 释放结果窗阶段资源（结果窗/编辑器/controller）。
    /// 结果窗关闭、ESC 关闭与新会话开始时调用。
    private func dismissScrollResult() {
        removeResultEscMonitor()
        scrollEditorWindow?.close()
        scrollEditorWindow = nil
        scrollResultPanel?.orderOut(nil)
        scrollResultPanel = nil
        scrollResultImage = nil
        scrollController = nil
    }

    /// 结果窗展示期间的 ESC 关闭监听（覆盖层 escMonitor 已随会话 finish 移除）。
    private func installResultEscMonitor() {
        removeResultEscMonitor()
        scrollResultEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  event.keyCode == ScreenshotSession.escKeyCode,
                  event.window === self.scrollResultPanel else { return event }
            DiagLog.write("Scroll result panel ESC -> close")
            self.dismissScrollResult()
            return nil
        }
    }

    private func removeResultEscMonitor() {
        if let monitor = scrollResultEscMonitor {
            NSEvent.removeMonitor(monitor)
            scrollResultEscMonitor = nil
        }
    }

    /// 结果窗「贴图」回调：复用普通截图的 PinWindow 逻辑。
    private func pinScrollImage(_ image: NSImage, at point: CGPoint) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            DiagLog.write("Scroll pin: NSImage -> CGImage conversion failed")
            return
        }
        let pin = PinWindow(cgImage: cgImage, displaySize: image.size, at: point, cornerRadius: 0)
        pin.onClose = { [weak self, weak pin] in
            guard let self = self, let pin = pin else { return }
            self.pinWindows.removeAll { $0 === pin }
        }
        pin.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pinWindows.append(pin)
        DiagLog.write("Scroll capture pinned at \(point), size=\(image.size)")
    }

    // MARK: - 长截图 UI

    /// 选区边框窗口：截帧排除锚点（.optionOnScreenBelowWindow 只采边框以下内容），
    /// 工具条/预览层级在其上同样被排除。返回创建的 panel。
    @discardableResult
    private func showScrollBorder(sel: CGRect, screen: NSScreen) -> NSPanel {
        let globalRect = CGRect(x: screen.frame.origin.x + sel.origin.x,
                                y: screen.frame.origin.y + sel.origin.y,
                                width: sel.width, height: sel.height)
        let panel = NSPanel(contentRect: globalRect,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.borderWidth = 2
        panel.contentView?.layer?.borderColor = NSColor.systemBlue.cgColor
        panel.orderFrontRegardless()
        return panel
    }

    /// 实时预览窗：按工具条 previewHostFrame 建无框透明 NSPanel，内嵌 LiveStitchPreviewView。
    /// 层级取 screenSaver+4（高于边框窗口），与工具条一样被截帧排除；
    /// 不接收鼠标事件（滚轮穿透到下层可滚动内容）。
    private func showScrollPreview(toolbar: ScrollCaptureToolbar) {
        let hostFrame = toolbar.previewHostFrame
        guard hostFrame.width > 0, hostFrame.height > 0 else {
            DiagLog.write("Scroll preview host frame unavailable, preview skipped")
            return
        }
        let panel = NSPanel(contentRect: hostFrame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        let view = LiveStitchPreviewView(frame: NSRect(origin: .zero, size: hostFrame.size))
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        panel.orderFrontRegardless()
        scrollPreviewPanel = panel
        scrollPreviewView = view
        DiagLog.write("Scroll live preview shown: frame=\(hostFrame)")
    }
}

// MARK: - ScrollCaptureToolbarDelegate 一致性（方法实现在类主体内）

extension ScreenshotCoordinator: ScrollCaptureToolbarDelegate {}

// MARK: - ScrollResultPanelDelegate

extension ScreenshotCoordinator: ScrollResultPanelDelegate {

    /// 保存：统一保存服务（成功 Finder 定位 + toast，失败弹错误提示，均在服务内完成）。
    /// 保存后保持结果窗打开，用户可继续复制/贴图/编辑。
    func resultPanelDidSave(_ panel: ScrollResultPanel) {
        guard let image = scrollResultImage else { return }
        saveService.save(image: image, config: .init())
    }

    /// 复制到剪贴板。
    func resultPanelDidCopy(_ panel: ScrollResultPanel) {
        guard let image = scrollResultImage else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        let ok = pb.writeObjects([image])
        DiagLog.write("Scroll result copied to pasteboard: ok=\(ok)")
        if ok { feedback.showCopied() }
    }

    /// 贴图到桌面：复用 PinWindow 流程（结果窗保持打开）。
    func resultPanelDidPin(_ panel: ScrollResultPanel) {
        guard let image = scrollResultImage else { return }
        pinScrollImage(image, at: scrollResultPinPoint)
    }

    /// 进入标注编辑：复用长图编辑器 ScrollImageEditorWindow（像素空间标注，
    /// 与普通截图的覆盖层标注链路互不依赖）；编辑完成回传新图并刷新结果窗。
    func resultPanelDidEdit(_ panel: ScrollResultPanel) {
        guard let image = scrollResultImage else { return }
        if let editor = scrollEditorWindow {
            editor.makeKeyAndOrderFront(nil)
            return
        }
        guard let editor = ScrollImageEditorWindow(
            image: image,
            onComplete: { [weak self] edited in
                guard let self = self else { return }
                self.scrollEditorWindow = nil
                self.scrollResultImage = edited
                // 编辑后标注已合入新图，拼接质量 issues 不再适用；强制重拼出口关闭（图已变更）
                self.scrollResultPanel?.show(image: edited, issues: [],
                                             canRetryForced: false, delegate: self)
            },
            onCancel: { [weak self] in
                self?.scrollEditorWindow = nil
            }) else {
            DiagLog.write("Scroll result edit: editor init failed (image data unavailable)")
            return
        }
        scrollEditorWindow = editor
        editor.present()
        DiagLog.write("Scroll result edit: editor opened")
    }

    /// 强制堆叠重拼：后台 stitchForced → 主线程刷新同一结果窗（不再提供二次强制）。
    func resultPanelDidRetryForced(_ panel: ScrollResultPanel) {
        guard let controller = scrollController, !scrollFinishing else { return }
        DiagLog.write("Scroll result: forced restitch triggered")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let forced = controller.stitchForced()
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let cgImage = forced, let current = self.scrollController else {
                    self.feedback.showCaptureFailed(message: "强制重拼失败：原始帧数据不可用")
                    return
                }
                let image = current.renderImage(cgImage)
                self.scrollResultImage = image
                self.scrollResultPanel?.show(
                    image: image,
                    issues: [ScrollResultIssueViewData(kind: .forcedStack, detail: "")],
                    canRetryForced: false,
                    delegate: self)
            }
        }
    }

    /// 关闭结果窗：释放结果窗阶段资源（含 controller）。
    func resultPanelDidClose(_ panel: ScrollResultPanel) {
        DiagLog.write("Scroll result panel closed")
        dismissScrollResult()
    }
}
