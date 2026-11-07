import Foundation
import CoreGraphics

/// GIF 录制导出规格（纯逻辑，TDD）：帧调度、命名、用户反馈文案。
/// 背景：GIF「功能无效」的体感根因是全程零反馈（开始/停止/保存无任何提示），
/// 且 0.5s 帧距回放卡顿——本规格统一调度与反馈契约，App 层按此执行。
public enum GIFExportPlan {

    /// 截帧间隔 0.25s（4fps）。
    public static let captureInterval: TimeInterval = 0.25

    /// GIF 帧延迟必须等于截帧间隔，否则回放变速卡顿。
    public static let gifDelayTime: Double = captureInterval

    /// 最长录制 60 秒（到时自动停止）。
    public static let maxDuration: TimeInterval = 60

    /// 帧数上限 = 时长 / 间隔。
    public static var maxFrames: Int { Int(maxDuration / captureInterval) }

    /// 半分辨率缩放（控制体积），奇数像素向上取整保证 ≥1。
    public static func scaledSize(pixelWidth: Int, pixelHeight: Int, scale: CGFloat = 0.5) -> CGSize {
        CGSize(width: ceil(CGFloat(pixelWidth) * scale),
               height: ceil(CGFloat(pixelHeight) * scale))
    }

    /// 保存文件名：「GIF yyyy-MM-dd HH.mm.ss.gif」——与录屏命名同构；
    /// timeZone 默认本地时区（呈现用户本地时间），测试显式注入固定时区保证确定性。
    public static func fileName(date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        return "GIF \(formatter.string(from: date)).gif"
    }

    /// 开始提示（告知如何停止——旧版按了开始无任何反馈、用户不知如何停）。
    public static let startToast = "开始录制 GIF · ⌥G 停止"

    /// 保存结果反馈：成功带帧数与时长，零帧/编码失败显式报错（不得静默）。
    public static func saveToast(frames: Int, duration: TimeInterval, success: Bool,
                                 fileName: String) -> String {
        guard success, frames > 0 else { return "GIF 录制失败（未捕获到有效帧）" }
        let seconds = Int(duration.rounded())
        return "GIF 已保存到桌面 · \(frames) 帧 · \(seconds) 秒 · \(fileName)"
    }
}
