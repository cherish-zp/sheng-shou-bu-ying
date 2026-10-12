import Foundation

/// 诊断日志工具：写入 ~/Library/Application Support/圣手捕影/diag.log。
/// 非沙盒 App 可写任意位置，便于调试热键/截图等问题。
/// 性能：串行队列 + 常驻 FileHandle + 缓存 formatter（此前每条日志新建
/// ISO8601DateFormatter 并 open/seek/write/close 一次，调用点多在主线程热路径）。
enum DiagLog {
    static let logURL: URL = {
        let dir = AppSupportDirectory.url
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diag.log")
    }()

    /// 串行写队列：保证行序，同时把 ISO8601DateFormatter（线程限定）约束到单线程。
    private static let queue = DispatchQueue(label: "com.zp.shengshoubuying.diag")
    private static let formatter = ISO8601DateFormatter()
    /// 常驻追加句柄（队列内独占使用）。
    private static var handle: FileHandle?

    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.sync {
            if handle == nil {
                handle = try? FileHandle(forWritingTo: logURL)
                handle?.seekToEndOfFile()
            }
            if let handle = handle {
                handle.write(data)
            } else {
                // 首次创建（文件不存在时 forWritingTo 失败）
                try? data.write(to: logURL)
                handle = try? FileHandle(forWritingTo: logURL)
                handle?.seekToEndOfFile()
            }
        }
    }
}
