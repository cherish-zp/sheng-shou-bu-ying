import Foundation

/// 所有可用工具的中央注册表。在 `init` 里添加新工具。
/// `shared` 供 App/扩展使用；测试可注入自定义工具集合。
public final class ToolRegistry {
    public static let shared = ToolRegistry()

    public let tools: [Tool]

    public init(tools: [Tool] = [CopyPathTool(), CreateFileTool(fileCreator: RequestFileCreator()), EnterTerminalTool()]) {
        self.tools = tools
    }

    public func tool(for id: String) -> Tool? {
        tools.first { $0.id == id }
    }
}
