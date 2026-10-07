import Foundation

/// 片段数据变更通知名；SnippetManager 保存后发送，AppDelegate 监听后重建菜单。
public extension Notification.Name {
    static let snippetsDidChange = Notification.Name("com.zp.shengshoubuying.snippetsDidChange")
}

/// 快速片段：保存文本内容，通过 key 快速复制到剪贴板。
public struct Snippet: Codable, Identifiable, Equatable {
    public let id: UUID
    public var key: String
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), key: String, content: String,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.key = key
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 片段存储纯逻辑：增删改查 + 搜索，key 唯一（不区分大小写）。
/// 持久化通过 loadFromJSON/encode 交给调用方，便于单测。
public struct SnippetStore {
    public private(set) var snippets: [Snippet] = []

    public init() {}

    /// 添加片段。key 不区分大小写且不能重复，重复返回 nil。
    @discardableResult
    public mutating func add(key: String, content: String) -> Snippet? {
        guard !snippets.contains(where: { $0.key.lowercased() == key.lowercased() }) else { return nil }
        let snippet = Snippet(key: key, content: content)
        snippets.append(snippet)
        return snippet
    }

    /// 更新指定片段的 key 和 content。key 不能与其他片段重复。
    @discardableResult
    public mutating func update(id: UUID, key: String, content: String) -> Bool {
        guard snippets.contains(where: { $0.id == id }) else { return false }
        if snippets.contains(where: { $0.id != id && $0.key.lowercased() == key.lowercased() }) {
            return false
        }
        if let idx = snippets.firstIndex(where: { $0.id == id }) {
            snippets[idx].key = key
            snippets[idx].content = content
            snippets[idx].updatedAt = Date()
            return true
        }
        return false
    }

    /// 删除指定片段。
    @discardableResult
    public mutating func delete(id: UUID) -> Bool {
        if let idx = snippets.firstIndex(where: { $0.id == id }) {
            snippets.remove(at: idx)
            return true
        }
        return false
    }

    /// 按 key 查找内容（不区分大小写），用于快速复制。
    public func content(forKey key: String) -> String? {
        snippets.first(where: { $0.key.lowercased() == key.lowercased() })?.content
    }

    /// 模糊搜索：匹配 key 或 content（不区分大小写），空查询返回全部。
    public func search(query: String) -> [Snippet] {
        guard !query.isEmpty else { return snippets }
        let q = query.lowercased()
        return snippets.filter {
            $0.key.lowercased().contains(q) || $0.content.lowercased().contains(q)
        }
    }

    /// 从 JSON 数据加载片段。
    public mutating func loadFromJSON(_ data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([Snippet].self, from: data) {
            snippets = loaded
        }
    }

    /// 编码为 JSON 数据。
    public func encodeToJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try? encoder.encode(snippets)
    }
}
