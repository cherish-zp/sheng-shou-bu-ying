import AppKit
import CoreGraphics

/// 取色会话控制器：串联「按屏持有捕获图 -> 全屏压暗覆盖层 -> 放大镜跟随 -> 单击复制 -> ESC 退出」。
/// 性能关键：每屏一次性 CGDisplayCreateImage 只保留 CGImage（IOSurface 惰性背书），
/// 每次鼠标移动把 ~40×40px 采样窗绘入小缓冲再读（ColorPixelBuffer.cropRect）——
/// 免去整屏 RGBA 常驻（5K 屏 ~59MB/屏）；跟随鼠标跨屏时对新屏惰性捕获（每屏一次）。
/// 已知假设：屏幕静态场景下取色值即真实值；屏幕内容变化不自动重捕（见交付报告）。
final class ColorPickerSession: NSObject {

    /// ESC = kVK_Escape(53)。
    static let escKeyCode: UInt16 = 53

    /// 放大镜参数：9× 放大、显示半径 75pt（直径 150pt）。
    static let magnification: CGFloat = 9
    static let magnifierRadiusInPoints: CGFloat = 75

    /// 会话结束回调（模块据此清引用）。
    var onFinish: (() -> Void)?

    /// 取色历史（模块持有的共享实例，跨会话累积，容量 5）。
    private let history: ColorHistory
    private let pasteboard: Pasteboard

    private var overlayWindows: [ColorPickerOverlayWindow] = []
    private var magnifierWindow: ColorMagnifierWindow?
    private var escMonitor: Any?

    /// 每屏捕获图（惰性填充）：key = displayID。只留 CGImage，不预解码整屏 RGBA。
    private struct ScreenBuffer {
        let screen: NSScreen
        let displayID: CGDirectDisplayID
        let image: CGImage
    }
    private var screenBuffers: [CGDirectDisplayID: ScreenBuffer] = [:]

    init(history: ColorHistory, pasteboard: Pasteboard = SystemPasteboard()) {
        self.history = history
        self.pasteboard = pasteboard
        super.init()
    }

    // MARK: - 会话生命周期

    func start() {
        // 会话期临时切 .accessory：.regular 应用的 fullScreenAuxiliary 窗口无法合成到
        // 其他应用的全屏 Space（macOS 26 实测，覆盖层/放大镜全屏下不渲染），.accessory 可以。
        // 结束（stop）恢复 .regular（Dock 常驻图标）。
        NSApp.setActivationPolicy(.accessory)
        DiagLog.write("activationPolicy -> accessory (color picker session)")
        requestScreenCapturePermission()

        let mouseScreen = screen(containing: NSEvent.mouseLocation) ?? NSScreen.main
        // 预捕获鼠标所在屏（跨屏时其余屏惰性捕获）
        if let mouseScreen = mouseScreen {
            primeBuffer(for: mouseScreen)
        }

        // 所有屏建压暗覆盖层（无焦点覆盖，轻微压暗 15%，不做选区）
        for screen in NSScreen.screens {
            let window = ColorPickerOverlayWindow(screen: screen)
            window.pickerView.onMouseMoved = { [weak self] in self?.refreshMagnifier() }
            window.pickerView.onPick = { [weak self] in self?.pickColor() }
            window.pickerView.onCancel = { [weak self] in self?.stop() }
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }

        // 鼠标所在屏设为 key：保证键盘（ESC）与首次点击直达覆盖层
        if let keyWindow = overlayWindows.first(where: { $0.screen == mouseScreen }) ?? overlayWindows.first {
            keyWindow.makeKeyAndOrderFront(nil)
            keyWindow.makeFirstResponder(keyWindow.pickerView)
        }
        // 不切换 activationPolicy（会话已在 start 进入 .accessory，stop 恢复 .regular）
        NSApp.activate(ignoringOtherApps: true)

        // 放大镜窗口 + ESC 本地监听兜底（覆盖层为 key 时视图 keyDown 已处理，此为第二道）
        magnifierWindow = ColorMagnifierWindow()
        installEscMonitor()
        refreshMagnifier()
        DiagLog.write("ColorPickerSession: started, screens=\(overlayWindows.count) primeScreen=\(mouseScreen.map { String(describing: $0.frame) } ?? "nil")")
    }

    /// 退出会话：收全部窗口、移除监听、释放预捕获缓冲。
    func stop() {
        if let escMonitor = escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        magnifierWindow?.orderOut(nil)
        magnifierWindow = nil
        for window in overlayWindows { window.orderOut(nil) }
        overlayWindows.removeAll()
        screenBuffers.removeAll()
        // 会话结束恢复 .regular（Dock 常驻图标）
        NSApp.setActivationPolicy(.regular)
        DiagLog.write("activationPolicy -> regular (color picker session ended)")
        DiagLog.write("ColorPickerSession: stopped")
        onFinish?()
    }

    // MARK: - 取样与取色

    /// 鼠标移动：刷新放大镜（网格 + 十字准星 + 色值条）。
    private func refreshMagnifier() {
        guard let magnifierWindow = magnifierWindow else { return }
        let location = NSEvent.mouseLocation
        guard let sample = sampleColor(at: location) else { return }
        guard let screen = screen(containing: location) else { return }
        magnifierWindow.update(location: location, screen: screen,
                               gridColors: sample.gridColors, cursorColor: sample.cursorColor,
                               hexText: sample.hex, rgbText: sample.rgb)
    }

    /// 单击取色：复制 #RRGGBB 到剪贴板 + Toast + 记录历史；取色器保持打开可连续取色。
    private func pickColor() {
        let location = NSEvent.mouseLocation
        guard let sample = sampleColor(at: location) else {
            DiagLog.write("ColorPickerSession: pick failed (no sample)")
            return
        }
        pasteboard.copy(sample.hex)
        history.record(sample.hex)
        TransientHudToast.show(text: "已复制 \(sample.hex) · \(sample.rgb)")
        DiagLog.write("ColorPickerSession: picked \(sample.hex) \(sample.rgb), history=\(history.entries)")
    }

    /// 取样结果：放大镜网格颜色 + 光标色 + 文本。
    private struct SampleResult {
        let gridColors: [[NSColor?]]
        let cursorColor: NSColor?
        let hex: String
        let rgb: String
    }

    /// 取样：屏幕点 → 位图像素（GridMath 换算含 scaleFactor 与 y 翻转）→ 采样窗小缓冲读取。
    private func sampleColor(at location: NSPoint) -> SampleResult? {
        guard let screen = screen(containing: location),
              let entry = buffer(for: screen) else { return nil }
        let imageSize = CGSize(width: entry.image.width, height: entry.image.height)
        let cursorPixel = ColorMagnifierGridMath.cursorPixel(
            cursorInScreen: location, screenFrame: screen.frame, imagePixelSize: imageSize)
        let points = ColorMagnifierGridMath.samplePoints(
            cursorPixel: cursorPixel, imageSize: imageSize,
            magnification: ColorPickerSession.magnification,
            magnifierRadiusInPoints: ColorPickerSession.magnifierRadiusInPoints,
            backingScale: screen.backingScaleFactor)
        guard !points.isEmpty,
              let region = ColorPixelBuffer.regionBounds(
                points: points.flatMap { $0 }, cursorPixel: cursorPixel, imageSize: imageSize),
              let window = ColorPixelBuffer(image: entry.image, cropRect: region) else { return nil }
        func read(_ p: CGPoint) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
            window.rgba(atX: Int(p.x.rounded()) - Int(region.minX),
                        y: Int(p.y.rounded()) - Int(region.minY))
        }
        let gridColors: [[NSColor?]] = points.map { row in
            row.map { point in
                guard let rgba = read(point) else { return nil }
                return NSColor(calibratedRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: 1)
            }
        }
        guard let rgba = read(cursorPixel) else { return nil }
        let hex = HexColorFormatter.hexString(red: rgba.red, green: rgba.green, blue: rgba.blue)
        let rgb = HexColorFormatter.rgbString(red: rgba.red, green: rgba.green, blue: rgba.blue)
        let cursorColor = NSColor(calibratedRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: 1)
        return SampleResult(gridColors: gridColors, cursorColor: cursorColor, hex: hex, rgb: rgb)
    }

    // MARK: - 预捕获（每屏一次）

    /// 进入时预捕获鼠标所在屏。
    private func primeBuffer(for screen: NSScreen) {
        _ = buffer(for: screen)
    }

    /// 惰性获取屏捕获图：缺失时对该屏一次性 CGDisplayCreateImage（不做整屏解码）。
    private func buffer(for screen: NSScreen) -> ScreenBuffer? {
        guard let displayID = displayID(of: screen) else { return nil }
        if let existing = screenBuffers[displayID] { return existing }
        guard let image = CGDisplayCreateImage(displayID) else {
            DiagLog.write("ColorPickerSession: CGDisplayCreateImage failed for \(displayID) (screen recording permission?)")
            return nil
        }
        let entry = ScreenBuffer(screen: screen, displayID: displayID, image: image)
        screenBuffers[displayID] = entry
        DiagLog.write("ColorPickerSession: primed capture display=\(displayID) pixels=\(image.width)x\(image.height)")
        return entry
    }

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func screen(containing location: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(location) }
    }

    // MARK: - 权限与 ESC

    /// 首次进入弹屏幕录制授权（未授权时捕获只返回壁纸，与截图模块行为一致）。
    private func requestScreenCapturePermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            DiagLog.write("ColorPickerSession: requesting screen capture permission")
        }
    }

    /// ESC 本地监听兜底：无论 first responder 在谁，ESC 一律退出取色器。
    private func installEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == ColorPickerSession.escKeyCode {
                DiagLog.write("ColorPickerSession: ESC pressed, exiting")
                self?.stop()
                return nil
            }
            return event
        }
    }
}
