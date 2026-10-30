import Foundation

/// 所有可用工具的中央注册表。在 `init` 里添加新工具。
/// `shared` 供 App/扩展使用；测试可注入自定义工具集合。
public final class ToolRegistry {
    public static let shared = ToolRegistry()

    public let tools: [Tool]

    public init(tools: [Tool] = [
        CopyPathTool(),
        CreateFileTool(fileCreator: RequestFileCreator()),
        EnterTerminalTool(),
        FolderActionTool(.paste),
        FolderActionTool(.copyTo),
        FolderActionTool(.moveTo),
        FolderActionTool(.deleteForever),
        FolderActionTool(.showHidden),
        FolderActionTool(.toggleExtension),
        NewDocumentTool(baseName: "新建文本文档.txt", title: "文本文档", symbol: "doc.plaintext", fileCreator: RequestFileCreator()),
        NewDocumentTool(baseName: "新建富文本.rtf", title: "富文本", symbol: "doc.richtext", fileCreator: RequestFileCreator()),
        NewDocumentTool(baseName: "新建WPS文字.wps", title: "WPS 文字", symbol: "doc.text", fileCreator: RequestFileCreator()),
        NewDocumentTool(baseName: "新建WPS表格.et", title: "WPS 表格", symbol: "tablecells", fileCreator: RequestFileCreator()),
        NewDocumentTool(baseName: "新建WPS演示.dps", title: "WPS 演示", symbol: "rectangle.stack", fileCreator: RequestFileCreator()),
        OpenCalendarTool(),
    ]) {
        self.tools = tools
    }

    public func tool(for id: String) -> Tool? {
        tools.first { $0.id == id }
    }
}
