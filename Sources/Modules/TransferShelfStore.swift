import Foundation

/// 文件中转条目。file 只保存 URL 引用，不复制文件本体；
/// text/image/link 把内容直接落在条目上（文本字符串、PNG data、URL）。
/// `url` 对所有 kind 都是去重键：file 用真实文件 URL，
/// text/image 用内容哈希合成的稳定 URL（见 TransferItemSyntheticURL），link 用链接本身。
public struct TransferItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let addedAt: Date
    /// 条目类型；旧版 JSON 缺省解码为 .file（向后兼容）。
    public let kind: TransferItemKind
    /// kind == .text 时的文本内容。
    public let text: String?
    /// kind == .image 时的 PNG 数据（JSON 中 Base64 编码）。
    public let imageData: Data?
    /// kind == .link 时的链接 URL。
    public let link: URL?

    public init(id: UUID = UUID(), url: URL, name: String? = nil, addedAt: Date = Date(),
                kind: TransferItemKind = .file, text: String? = nil,
                imageData: Data? = nil, link: URL? = nil) {
        self.id = id
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.addedAt = addedAt
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.link = link
    }

    /// text 条目：名称取首行摘要（截断到 80 字符），去重键为内容哈希合成 URL。
    public static func text(_ content: String) -> TransferItem {
        TransferItem(
            url: TransferItemSyntheticURL.textURL(content: content),
            name: Self.textName(content),
            kind: .text,
            text: content
        )
    }

    /// image 条目：PNG 数据进条目，去重键为数据哈希合成 URL。
    public static func image(_ pngData: Data) -> TransferItem {
        TransferItem(
            url: TransferItemSyntheticURL.imageURL(pngData: pngData),
            name: "图片",
            kind: .image,
            imageData: pngData
        )
    }

    /// link 条目：去重键即链接本身，名称为 host + path。
    public static func link(_ url: URL) -> TransferItem {
        TransferItem(
            url: url,
            name: Self.linkName(url),
            kind: .link,
            link: url
        )
    }

    /// 首行摘要：取第一行并去掉首尾空白，截断到 80 字符（防 JSON 膨胀与展示溢出）。
    private static func textName(_ content: String) -> String {
        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first.map(String.init) ?? content
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "(空白文本)" }
        return String(trimmed.prefix(80))
    }

    /// link 名称：host + path（如 docs.example.com/guide/intro）。
    private static func linkName(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path
        let joined = path.isEmpty ? host : host + path
        return String(joined.prefix(80))
    }
}

extension TransferItem {

    /// 旧版 JSON（无 kind 字段）向后兼容解码：kind 缺省 .file，载荷字段缺省 nil。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        name = try container.decode(String.self, forKey: .name)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        kind = try container.decodeIfPresent(TransferItemKind.self, forKey: .kind) ?? .file
        text = try container.decodeIfPresent(String.self, forKey: .text)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        link = try container.decodeIfPresent(URL.self, forKey: .link)
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, name, addedAt, kind, text, imageData, link
    }
}

/// 文件中转站存储纯逻辑：URL 引用式暂存、去重、条目上限、删除、持久化、失效检测。
/// 文件系统访问通过 fileExists 闭包注入，便于单测。
public struct TransferShelfStore {
    public private(set) var items: [TransferItem] = []

    /// 条目上限，add 超限时淘汰最旧条目（init 可注入，默认 20）。
    public let maxCount: Int

    public init(maxCount: Int = 20) {
        precondition(maxCount >= 1, "maxCount 至少为 1")
        self.maxCount = maxCount
    }

    /// 添加文件 URL。同一 URL 已存在时返回 nil（去重，且不触发淘汰）。
    /// 超过 maxCount 时移除最旧的条目腾位。
    @discardableResult
    public mutating func add(url: URL) -> TransferItem? {
        add(item: TransferItem(url: url))
    }

    /// 添加任意 kind 的条目。去重键为 item.url（file 真实 URL / text、image
    /// 内容哈希合成 URL / link 链接本身）；同一 URL 已存在时返回 nil。
    /// 超过 maxCount 时移除最旧的条目腾位——上限计数对所有 kind 统一。
    @discardableResult
    public mutating func add(item: TransferItem) -> TransferItem? {
        guard !items.contains(where: { $0.url == item.url }) else { return nil }
        if items.count >= maxCount {
            items.removeFirst(items.count - maxCount + 1)
        }
        items.append(item)
        return item
    }

    /// 移除指定条目。
    @discardableResult
    public mutating func remove(id: UUID) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return false }
        items.remove(at: idx)
        return true
    }

    /// 清空全部条目。
    public mutating func clear() {
        items.removeAll()
    }

    /// 编码为 JSON 数据，交给调用方持久化。
    public func encode() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(items)
    }

    /// 从 JSON 数据恢复。解码失败返回 nil（不再无声清空），
    /// 由调用方负责备份损坏文件；成功但超长时裁剪到 maxCount 内（保留最新）。
    public static func load(from data: Data, maxCount: Int = 20) -> TransferShelfStore? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var items = try? decoder.decode([TransferItem].self, from: data) else {
            return nil
        }
        if items.count > maxCount {
            items.removeFirst(items.count - maxCount)
        }
        var store = TransferShelfStore(maxCount: maxCount)
        store.items = items
        return store
    }

    /// 条目是否仍然有效：只有 file kind 检查文件存在性（text/image/link
    /// 内容自带在条目上，永不过期）。
    public func isValid(_ item: TransferItem, fileExists: (URL) -> Bool) -> Bool {
        guard item.kind.requiresFileExistenceCheck else { return true }
        return fileExists(item.url)
    }

    /// 移除所有失效条目（文件已不存在的 file 条目），返回被移除的条目（保持原顺序）。
    /// 非 file kind 跳过 fileExists，永不因文件检查被移除；fileExists 注入便于单测。
    @discardableResult
    public mutating func purgeInvalid(fileExists: (URL) -> Bool) -> [TransferItem] {
        var kept: [TransferItem] = []
        var removed: [TransferItem] = []
        for item in items {
            if isValid(item, fileExists: fileExists) {
                kept.append(item)
            } else {
                removed.append(item)
            }
        }
        items = kept
        return removed
    }
}
