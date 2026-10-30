import Foundation

/// 文件夹动作请求（扩展 → App）：粘贴/复制至/移动到/彻底删除/显示隐藏文件/扩展名开关。
/// 与 CreateFileRequest 同队列（扩展可写、App 轮询消费）；JSON 以 "action" 字段区分类型。
public struct FolderActionRequest: Codable {
    public enum Action: String, Codable {
        case paste          // 剪贴板文件粘贴到 directory
        case copyTo         // paths 复制到用户选择的文件夹
        case moveTo         // paths 移动到用户选择的文件夹
        case deleteForever  // 彻底删除 paths（不可恢复，App 侧强制确认）
        case showHidden     // 切换 Finder 显示隐藏文件
        case toggleExtension // 切换 Finder 显示文件扩展名
    }

    public let action: Action
    public let directory: String
    public let paths: [String]

    public init(action: Action, directory: String, paths: [String] = []) {
        self.action = action
        self.directory = directory
        self.paths = paths
    }
}

/// 扩展侧写入器：把文件夹动作请求原子写入队列目录。
public final class FolderActionRequestWriter {
    private let queueDirectory: URL

    public init(queueDirectory: URL = ToolConfig.directoryURL.appendingPathComponent("requests", isDirectory: true)) {
        self.queueDirectory = queueDirectory
    }

    public func write(_ request: FolderActionRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        try? FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        let name = UUID().uuidString
        let tmp = queueDirectory.appendingPathComponent(name + ".tmp")
        let final = queueDirectory.appendingPathComponent(name + ".json")
        try? data.write(to: tmp, options: .atomic)
        try? FileManager.default.moveItem(at: tmp, to: final)
    }
}
