import Foundation

/// 截图输出格式。
public enum ScreenshotFormat: String, Codable, CaseIterable {
    case png
    case jpg

    public var fileExtension: String { rawValue }
}

/// 截图配置：保存目录、格式、文件名前缀。Codable 便于持久化到用户偏好。
public struct ScreenshotConfig: Codable, Equatable {
    public var saveDirectory: URL
    public var format: ScreenshotFormat
    public var filenamePrefix: String

    public init(
        saveDirectory: URL? = nil,
        format: ScreenshotFormat = .png,
        filenamePrefix: String = "截屏"
    ) {
        self.saveDirectory = saveDirectory ?? ScreenshotConfig.defaultSaveDirectory
        self.format = format
        self.filenamePrefix = filenamePrefix
    }

    /// 默认保存目录：~/Pictures/Screenshots
    public static let defaultSaveDirectory: URL = {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        return pictures?.appendingPathComponent("Screenshots")
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }()
}

/// 根据日期与配置生成截图文件名，复用 FileNameResolver 做去重。
public enum ScreenshotFileNameBuilder {
    /// 基础文件名（不含扩展名），格式与 macOS 系统截图一致："截屏 2026-08-01 14.44.33"。
    /// timeZone 默认本地时区（文件名呈现用户本地时间），测试显式注入固定时区。
    public static func baseName(
        date: Date,
        prefix: String = "截屏",
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        return "\(prefix) \(formatter.string(from: date))"
    }

    /// 生成去重后的完整文件名（含扩展名），避免覆盖同名截图。
    public static func uniqueFileName(
        date: Date,
        config: ScreenshotConfig,
        existingNames: Set<String>,
        timeZone: TimeZone = .current
    ) -> String {
        let base = baseName(date: date, prefix: config.filenamePrefix, timeZone: timeZone)
        let fullName = "\(base).\(config.format.fileExtension)"
        return FileNameResolver.unique(baseName: fullName, existingNames: existingNames)
    }
}
