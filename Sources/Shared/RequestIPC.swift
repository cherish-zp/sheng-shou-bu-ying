import Foundation

/// 扩展<->App 的 IPC 配置与实现。
/// 扩展(沙盒)不能直接写用户目录，故把"新建文件"请求写成 JSON 文件放入队列目录，
/// 非沙盒的菜单栏 App 轮询该目录并真正建文件。
/// 队列目录在扩展容器内（扩展可写、App 可读），路径须与扩展内 ToolConfig.directoryURL/requests 一致。
public enum IPCConfig {
    /// 扩展 bundle ID 必须以主应用 bundle ID 为前缀（嵌入扩展校验要求），
    /// 更名后随之变更；扩展容器数据不迁移（工具开关默认全开，无用户数据损失）。
    public static let extensionBundleID = "com.zp.shengshoubuying.FinderSyncExt"

    /// 扩展容器的请求队列目录（App 读取用）。
    public static func extensionRequestDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(extensionBundleID)/Data/Library/Application Support/\(AppSupportDirectory.currentName)/requests", isDirectory: true)
    }
}

/// 扩展侧 FileCreator：把请求原子写入队列目录（先写 .tmp 再 rename，避免 App 读到半截文件）。
public final class RequestFileCreator: FileCreator {
    private let queueDirectory: URL

    public init(queueDirectory: URL = ToolConfig.directoryURL.appendingPathComponent("requests", isDirectory: true)) {
        self.queueDirectory = queueDirectory
    }

    public func createFile(in directory: URL, baseName: String) {
        let request = CreateFileRequest(directory: directory, baseName: baseName)
        guard let data = try? JSONEncoder().encode(request) else { return }
        try? FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        let name = UUID().uuidString
        let tmp = queueDirectory.appendingPathComponent(name + ".tmp")
        let final = queueDirectory.appendingPathComponent(name + ".json")
        try? data.write(to: tmp, options: .atomic)
        // 原子重命名：文件出现即完整。
        try? FileManager.default.moveItem(at: tmp, to: final)
    }
}

/// App 侧请求处理器：扫描队列目录的 .json 请求，逐个建文件并删除请求（处理失败也删除，避免队列卡死）。
public final class RequestProcessor {
    private let queueDirectory: URL
    private let service: CreateFileService

    public init(queueDirectory: URL, service: CreateFileService = CreateFileService()) {
        self.queueDirectory = queueDirectory
        self.service = service
    }

    /// 处理队列中所有请求，返回成功处理数。
    @discardableResult
    public func processAll() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: queueDirectory, includingPropertiesForKeys: nil)) ?? []
        var processed = 0
        for file in files where file.pathExtension == "json" {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file),
                  let request = try? JSONDecoder().decode(CreateFileRequest.self, from: data) else {
                continue
            }
            _ = service.createFile(request: request)
            processed += 1
        }
        return processed
    }
}
