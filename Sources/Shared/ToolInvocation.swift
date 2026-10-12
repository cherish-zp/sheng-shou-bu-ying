import Foundation

/// 一次工具调用：工具 id + 当次选中的 urls。
public struct ToolInvocation {
    public let toolId: String
    public let urls: [URL]
    public init(toolId: String, urls: [URL]) {
        self.toolId = toolId
        self.urls = urls
    }
}

/// 菜单项调用表：用 NSMenuItem.tag 作为下标找回调用。
/// 原因：Finder Sync 菜单项的 representedObject(任意对象)跨进程到 Finder 时不被保留，
/// 而 tag(原始 Int)会保留。故用 tag + 本表传递 {工具id, urls}。
///
/// tag 编码代次：`generation * stride + index`。Finder 可能对同一次交互多次回调
/// menu(for:)，或在上一次菜单未点击前再次构建——若 tag 只是纯下标，旧菜单项会
/// 静默命中"另一次构建"的调用（工具/路径错位）。clear 递增代次（不归零），
/// 陈旧代次的 tag 解析为 nil。
public final class ToolInvocationTable {
    /// 单代最大条目数：右键菜单工具数量远小于此。
    private static let stride = 1024

    public private(set) var invocations: [ToolInvocation] = []
    /// 当前代次：单调递增，clear 后旧代 tag 全部失效。
    public private(set) var generation = 0

    @discardableResult
    public func append(_ invocation: ToolInvocation) -> Int {
        invocations.append(invocation)
        return generation * Self.stride + invocations.count - 1
    }

    public func clear() {
        invocations.removeAll()
        generation += 1
    }

    public func resolve(tag: Int) -> ToolInvocation? {
        guard tag >= 0 else { return nil }
        let tagGeneration = tag / Self.stride
        let index = tag % Self.stride
        guard tagGeneration == generation, index < invocations.count else { return nil }
        return invocations[index]
    }
}
