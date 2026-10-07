import Foundation

/// 录屏文件名构建：「录屏 yyyy-MM-dd HH.mm.ss.mp4」，复用 FileNameResolver 去重。
/// 与 ScreenshotFileNameBuilder 同构（macOS 系统截图命名风格）。
public enum RecordingFileNameBuilder {

    public static let fileExtension = "mp4"
    public static let defaultPrefix = "录屏"

    /// 基础文件名（不含扩展名）。timeZone 默认本地时区（文件名呈现用户本地时间），
    /// 测试显式注入固定时区以保证跨时区确定性（CI runner 为 UTC）。
    public static func baseName(
        date: Date,
        prefix: String = defaultPrefix,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        return "\(prefix) \(formatter.string(from: date))"
    }

    /// 生成去重后的完整文件名（含扩展名），避免覆盖同名录屏。
    public static func uniqueFileName(
        date: Date,
        prefix: String = defaultPrefix,
        existingNames: Set<String>,
        timeZone: TimeZone = .current
    ) -> String {
        let base = baseName(date: date, prefix: prefix, timeZone: timeZone)
        let fullName = "\(base).\(fileExtension)"
        return FileNameResolver.unique(baseName: fullName, existingNames: existingNames)
    }
}
