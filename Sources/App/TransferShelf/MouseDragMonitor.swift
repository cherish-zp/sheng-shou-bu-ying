import AppKit
import CoreGraphics

/// 全局鼠标拖拽监听：CGEventTap 监听按下/拖动/松开，
/// 用 TransferShelfDragPolicy 判定拖拽会话，驱动顶部中转面板显示。
///
/// tap 生命周期设计：
/// - 本监听从不修改/吞掉事件，因此用 `.listenOnly`（listen-only tap）而非
///   `.defaultTap`：不进入可修改事件的关键管线，全局开销更低；
/// - refcon 用 `passRetained(self)` 持有、stop() 里配对 `release`——
///   此前 passUnretained 在监听者提前释放时会悬垂；
/// - stop() 完整注销：tapEnable(false) → 移除 runloop source → CFMachPortInvalidate
///   → 释放 refcon。此前 stop() 只摘 runloop source，tap 本体一直存活；
/// - tap 被系统禁用（超时/用户输入）时重新启用（listen tap 一般不会超时，保底）。
final class MouseDragMonitor {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// passRetained 的自身引用，teardown 时 release（与 tapCreate 配对）。
    private var retainedSelf: Unmanaged<MouseDragMonitor>?
    /// 一次按下-松开手势内的屏幕快照：dragged 高频路径不再反复查询 NSScreen.screens。
    private var gestureScreens: [NSScreen] = []
    private var policy = TransferShelfDragPolicy()
    private var onDragStart: (() -> Void)?
    private var onDragEnd: (() -> Void)?
    private var onHotZoneHover: (() -> Void)?

    /// 同一进程会话只提示一次辅助功能权限缺失。
    private static var didPresentPermissionAlert = false

    /// 启动监听。回调自动派发到主线程。
    /// onHotZoneHover：拖拽过程中鼠标进入任意屏幕顶部中央热区（几何兜底）。
    func start(onDragStart: @escaping () -> Void,
               onDragEnd: @escaping () -> Void,
               onHotZoneHover: @escaping () -> Void) {
        stop()
        self.onDragStart = onDragStart
        self.onDragEnd = onDragEnd
        self.onHotZoneHover = onHotZoneHover
        policy.reset()
        gestureScreens = []

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<MouseDragMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.reenableTap()
            }
            return Unmanaged.passUnretained(event)
        }

        let retained = Unmanaged.passRetained(self)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: retained.toOpaque()
        ) else {
            // passRetained 已持有，创建失败必须释放，否则泄漏。
            retained.release()
            DiagLog.write("MouseDragMonitor: tapCreate FAILED（辅助功能权限缺失？）")
            Self.presentPermissionAlertOnce()
            return
        }
        retainedSelf = retained

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        DiagLog.write("MouseDragMonitor: started (listenTap)")
    }

    /// 完整注销 tap：禁用 → 摘 source → invalidate → 释放 refcon。
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        retainedSelf?.release()
        retainedSelf = nil
        onDragStart = nil
        onDragEnd = nil
        onHotZoneHover = nil
        policy.reset()
        gestureScreens = []
    }

    /// tap 被系统禁用后自恢复。
    private func reenableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        DiagLog.write("MouseDragMonitor: tap re-enabled after disable")
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDown:
            // 每次手势开始快照屏幕，后续 dragged 事件直接用快照换算/判热区。
            gestureScreens = NSScreen.screens
            policy.mouseDown(at: appKitLocation(event.location))
        case .leftMouseDragged:
            // 无 mouseDown 的 dragged（如其他进程注入的事件流）：补一次快照兜底。
            if gestureScreens.isEmpty {
                gestureScreens = NSScreen.screens
            }
            let location = appKitLocation(event.location)
            if policy.mouseDragged(to: location) {
                DispatchQueue.main.async { [weak self] in
                    self?.onDragStart?()
                }
            }
            if policy.isDragging {
                let inHotZone = gestureScreens.contains { screen in
                    TransferShelfLayoutSpec.isInHotZone(
                        location: location,
                        visibleFrame: screen.visibleFrame
                    )
                }
                if policy.hotZoneHoverChanged(inside: inHotZone), inHotZone {
                    DispatchQueue.main.async { [weak self] in
                        self?.onHotZoneHover?()
                    }
                }
            }
        case .leftMouseUp:
            if policy.isDragging {
                policy.mouseUp()
                DispatchQueue.main.async { [weak self] in
                    self?.onDragEnd?()
                }
            } else {
                policy.mouseUp()
            }
        default:
            break
        }
    }

    /// CG 全局坐标（左上原点、以原点屏为基准）转 AppKit 坐标（左下原点）。
    /// 基准屏是 frame.origin == (0,0) 的屏——多屏时 screens.first 未必是它，
    /// 用它换算会导致坐标整体偏移。
    private func appKitLocation(_ cg: CGPoint) -> CGPoint {
        let baseHeight = gestureScreens.first { $0.frame.origin == .zero }?.frame.height
            ?? gestureScreens.first?.frame.height ?? 0
        return CGPoint(x: cg.x, y: baseHeight - cg.y)
    }

    /// tapCreate 失败时的显式提示（同一会话仅一次）：
    /// 拖拽自动呼出依赖辅助功能权限，静默失败会让用户以为功能坏了。
    /// 弹窗层级与截图/录屏错误提示同风格（screenSaver+3，避免被覆盖层遮挡）。
    private static func presentPermissionAlertOnce() {
        DispatchQueue.main.async {
            guard !didPresentPermissionAlert else { return }
            didPresentPermissionAlert = true
            DiagLog.write("MouseDragMonitor: 提示用户授予辅助功能权限（拖拽自动呼出不可用）")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "无法启用「拖拽自动呼出」"
            alert.informativeText = "文件中转站需要辅助功能权限，才能在拖拽文件时自动呼出顶部面板。F2 手动呼出不受影响。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后再说")
            alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
