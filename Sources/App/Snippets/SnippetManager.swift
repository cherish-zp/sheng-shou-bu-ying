import AppKit

/// 片段管理器：封装 SnippetStore + JSON 文件持久化 + 剪贴板复制。
/// 菜单栏和管理窗口通过此类读写片段。
final class SnippetManager {

    static let shared = SnippetManager()

    private var store = SnippetStore()
    private let storageURL: URL

    private init() {
        let dir = AppSupportDirectory.url
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("snippets.json")
        load()
    }

    var snippets: [Snippet] { store.snippets }

    /// 添加片段，成功后自动保存。
    @discardableResult
    func add(key: String, content: String) -> Snippet? {
        let result = store.add(key: key, content: content)
        if result != nil { save() }
        return result
    }

    /// 更新片段，成功后自动保存。
    @discardableResult
    func update(id: UUID, key: String, content: String) -> Bool {
        let ok = store.update(id: id, key: key, content: content)
        if ok { save() }
        return ok
    }

    /// 删除片段，成功后自动保存。
    @discardableResult
    func delete(id: UUID) -> Bool {
        let ok = store.delete(id: id)
        if ok { save() }
        return ok
    }

    /// 按 key 复制内容到剪贴板。
    func copyToPasteboard(forKey key: String) -> Bool {
        guard let content = store.content(forKey: key) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
        return true
    }

    /// 搜索片段。
    func search(query: String) -> [Snippet] {
        store.search(query: query)
    }

    /// 从文件加载。
    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        store.loadFromJSON(data)
        DiagLog.write("SnippetManager: loaded \(store.snippets.count) snippets")
    }

    /// 保存到文件。
    func save() {
        guard let data = store.encodeToJSON() else { return }
        try? data.write(to: storageURL, options: .atomic)
        NotificationCenter.default.post(name: .snippetsDidChange, object: nil)
    }
}
