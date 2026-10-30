import AppKit
import Foundation

/// Finder 右键「进入终端」：在选中的目录打开终端（多选/文件取公共父目录）。
/// 通过 NSWorkspace 在扩展进程中打开终端 App，无需走 App 侧 IPC。
public final class EnterTerminalTool: Tool {
    public let id = "enter-terminal"
    public let title = "进入终端"

    public init() {}

    public func canPerform(on urls: [URL]) -> Bool {
        !urls.isEmpty
    }

    public func perform(on urls: [URL]) {
        let directory = commonDirectory(of: urls)
        guard let terminalURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal") else {
            NSLog("[EnterTerminalTool] 未找到终端 App")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [directory.path]
        NSWorkspace.shared.open([directory], withApplicationAt: terminalURL,
                                configuration: configuration)
    }

    /// 多个选中项取共同父目录；单目录直接用；单文件用其所在目录。
    private func commonDirectory(of urls: [URL]) -> URL {
        let resolved = urls.map { url -> URL in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue ? url : url.deletingLastPathComponent()
        }
        guard resolved.count > 1, let first = resolved.first else {
            return resolved.first ?? URL(fileURLWithPath: NSHomeDirectory())
        }
        // 逐级向上找共同祖先（路径前缀匹配，含自身）
        var ancestor = first
        while !resolved.allSatisfy({ $0.path.hasPrefix(ancestor.path) }) {
            guard ancestor.path != "/" else { break }
            ancestor = ancestor.deletingLastPathComponent()
        }
        return ancestor
    }
}
