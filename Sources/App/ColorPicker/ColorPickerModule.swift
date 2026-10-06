import AppKit
import CoreGraphics

/// 取色器模块（AppModule）：F5 或菜单触发，进入全屏覆盖层取色会话。
/// 交互：全屏轻微压暗（15%）→ 放大镜跟随鼠标（9× 放大 + 十字准星 + 色值条）
/// → 单击复制 #RRGGBB（Toast 提示），保持打开可连续取色，ESC 退出。
/// 性能策略：进入时对鼠标所在屏一次性预捕获整屏位图（ColorPixelBuffer），
/// 放大镜像素全部从该位图读取（零重复采集开销）；跨屏时对目标屏惰性捕获。
/// 屏幕为静态的假设下取色值即真实值（屏幕内容变化不自动重捕，见交付报告已知限制）。
final class ColorPickerModule: AppModule {

    let id = "color-picker"
    let title = "取色器"
    /// F5 = kVK_F5(96)，取色器默认快捷键。
    let defaultHotkey = Hotkey.f5

    /// 最近取色历史（容量 5，#RRGGBB，内存态不落盘）。
    /// v1 无 UI，仅暴露数组属性供未来挂菜单展示。
    public private(set) var history = ColorHistory()

    private var session: ColorPickerSession?

    /// 触发取色会话；会话已打开时忽略（防重复叠加覆盖层）。
    func perform() {
        guard session == nil else {
            DiagLog.write("ColorPickerModule: session already active, ignoring")
            return
        }
        let newSession = ColorPickerSession(history: history)
        newSession.onFinish = { [weak self] in
            self?.session = nil
        }
        newSession.start()
        session = newSession
        DiagLog.write("ColorPickerModule: session started")
    }
}
