import AppKit
import Foundation

/// Finder 右键文件夹动作工具族：动作经 FolderActionRequestWriter 走 IPC，
/// 由非沙盒 App 侧 FolderActionService 真正执行（含 UI 确认）。
public final class FolderActionTool: Tool {
    public enum Kind {
        case paste, copyTo, moveTo, deleteForever, showHidden, toggleExtension, compress, extract

        var id: String {
            switch self {
            case .paste: return "paste-into"
            case .copyTo: return "copy-to"
            case .moveTo: return "move-to"
            case .deleteForever: return "delete-forever"
            case .showHidden: return "show-hidden"
            case .toggleExtension: return "toggle-extension"
            case .compress: return "compress"
            case .extract: return "extract"
            }
        }

        var title: String {
            switch self {
            case .paste: return "粘贴"
            case .copyTo: return "复制至文件夹…"
            case .moveTo: return "移动到文件夹…"
            case .deleteForever: return "彻底删除"
            case .showHidden: return "显示/隐藏文件"
            case .toggleExtension: return "显示/隐藏扩展名"
            case .compress: return "压缩"
            case .extract: return "解压"
            }
        }
    }

    public let id: String
    public let title: String
    private let kind: Kind
    private let writer: FolderActionRequestWriter

    public init(_ kind: Kind, writer: FolderActionRequestWriter = FolderActionRequestWriter()) {
        self.kind = kind
        self.id = kind.id
        self.title = kind.title
        self.writer = writer
    }

    public func canPerform(on urls: [URL]) -> Bool {
        switch kind {
        case .paste, .showHidden, .toggleExtension: return !urls.isEmpty
        default: return !urls.isEmpty
        }
    }

    public func perform(on urls: [URL]) {
        // 目录语义与 CreateFileTool 一致：选中文件夹用其内部，文件用所在目录
        var isDir: ObjCBool = false
        let first = urls[0]
        FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir)
        let directory = isDir.boolValue ? first : first.deletingLastPathComponent()

        let paths: [String]
        switch kind {
        case .paste, .showHidden, .toggleExtension: paths = [directory.path]
        case .compress, .extract, .copyTo, .moveTo, .deleteForever: paths = urls.map(\.path)
        }
        let action: FolderActionRequest.Action
        switch kind {
        case .paste: action = .paste
        case .copyTo: action = .copyTo
        case .moveTo: action = .moveTo
        case .deleteForever: action = .deleteForever
        case .showHidden: action = .showHidden
        case .toggleExtension: action = .toggleExtension
        case .compress: action = .compress
        case .extract: action = .extract
        }
        writer.write(FolderActionRequest(action: action, directory: directory.path, paths: paths))
    }
}

/// 新建套件：固定文件名的新建工具（文本文档/富文本/WPS 三件套），复用建文件 IPC。
public final class NewDocumentTool: Tool {
    public let id: String
    public let title: String
    public let image: NSImage?
    private let baseName: String
    private let fileCreator: FileCreator
    private let inspector: FileSystemInspector

    public init(baseName: String, title: String, symbol: String,
                fileCreator: FileCreator, inspector: FileSystemInspector = SystemFileSystemInspector()) {
        self.baseName = baseName
        self.title = title
        self.id = "new-doc-\(baseName)"
        self.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        self.fileCreator = fileCreator
        self.inspector = inspector
    }

    public func perform(on urls: [URL]) {
        guard let first = urls.first else { return }
        let target = inspector.isDirectory(first) ? first : first.deletingLastPathComponent()
        fileCreator.createFile(in: target, baseName: baseName)
    }
}

/// Finder 右键「浮引日历」对标：打开系统日历。
public final class OpenCalendarTool: Tool {
    public let id = "open-calendar"
    public let title = "日历"

    public init() {}

    public func perform(on urls: [URL]) {
        if let calendarURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: calendarURL, configuration: .init())
        }
    }
}
