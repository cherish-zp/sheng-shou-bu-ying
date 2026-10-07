import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// 保持 .regular（LSUIElement=false）：Dock 常驻图标。勿改为 .accessory，
// 覆盖层可见性由各窗口的 canJoinAllSpaces + fullScreenAuxiliary 保证，不依赖策略。
application.run()
