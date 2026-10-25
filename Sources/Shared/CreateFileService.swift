import Foundation

/// 「新建文件」请求的输入校验（纯函数，TDD）。
/// 请求队列在扩展容器内，同用户任意进程都可投递 JSON——非沙盒 App 执行前必须过滤：
/// - baseName 白名单：非空、无路径分隔符/零字节、≤255 字节（文件名分量语义）；
/// - directory 黑名单：LaunchAgents / LaunchDaemons / StartupItems（登录项持久化位）
///   与 /System、/Library 系统根，防止把 App 当成任意路径写文件的跳板。
public enum CreateFileRequestValidator {

    private static let maxBaseNameUTF8Bytes = 255

    public static func isAllowed(directoryPath: String, baseName: String) -> Bool {
        guard !baseName.isEmpty,
              baseName != " ",
              !baseName.contains("/"),
              !baseName.contains("\0"),
              baseName.utf8.count <= maxBaseNameUTF8Bytes else { return false }

        // 折叠重复分隔符（"/Library//LaunchAgents" 与标准写法等效）
        let normalized = "/" + directoryPath.split(separator: "/").joined(separator: "/")
        if normalized == "/System" || normalized == "/Library" { return false }
        if normalized.hasPrefix("/System/") || normalized.hasPrefix("/Library/") { return false }
        // 登录项持久化位（含用户主目录下的同名路径）：contains 匹配——任何位置出现
        // 这些段名都拒绝，误伤面可忽略（正常不会有人往叫 LaunchAgents 的目录建文件）
        for marker in ["/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/StartupItems"] {
            if normalized.contains(marker) { return false }
        }
        return true
    }
}

/// App 侧建文件服务（非沙盒，可写任意目录）：按目录现有文件名去重后创建空文件。
/// 由菜单栏 App 监听扩展发来的请求队列并调用本服务（入参先经校验器过滤）。
public final class CreateFileService {
    public init() {}

    /// 依据请求在指定目录创建文件，返回创建的文件 URL（校验不过/失败返回 nil）。
    @discardableResult
    public func createFile(request: CreateFileRequest) -> URL? {
        createFile(in: request.directory, baseName: request.baseName)
    }

    /// 在 directory 内按 baseName 创建空文件，文件名与目录现有文件冲突时自动去重。
    @discardableResult
    public func createFile(in directory: URL, baseName: String) -> URL? {
        guard CreateFileRequestValidator.isAllowed(directoryPath: directory.path, baseName: baseName) else {
            NSLog("[CreateFileService] 拒绝非法请求 directory=\(directory.path) baseName=\(baseName.prefix(40))")
            return nil
        }
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let name = FileNameResolver.unique(baseName: baseName, existingNames: Set(existing))
        let url = directory.appendingPathComponent(name)
        let created = FileManager.default.createFile(atPath: url.path, contents: nil)
        return created ? url : nil
    }
}
