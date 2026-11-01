import AppKit
import ServiceManagement

/// 开机启动（对标浮引「开机启动」开关）：SMAppService 主应用注册。
enum StartupLauncher {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("[StartupLauncher] failed: \(error.localizedDescription)")
        }
    }
}
