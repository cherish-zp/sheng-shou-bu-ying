import Foundation

/// 剪贴板历史条目（文本；图片/文件以负载字符串记录）。
public struct ClipboardHistoryItem: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable {
        case text, image, files
    }

    public let id: UUID
    public let kind: Kind
    /// 文本内容；image/files 为摘要（image 存 PNG data 的 base64 太重——图片条目存路径化摘要，
    /// 实际图片数据由 App 层的独立缓存持有）。
    public let text: String
    public let imageData: Data?
    public let filePaths: [String]?
    public var addedAt: Date
    public var isFavorite: Bool

    public init(id: UUID = UUID(), kind: Kind, text: String, imageData: Data? = nil,
                filePaths: [String]? = nil, addedAt: Date = Date(), isFavorite: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.filePaths = filePaths
        self.addedAt = addedAt
        self.isFavorite = isFavorite
    }
}

/// 剪贴板历史存储（纯逻辑，TDD）：入队去重、收藏置顶、容量上限（收藏不计入淘汰）。
public struct ClipboardHistoryStore: Codable, Equatable {
    public static let defaultCapacity = 50

    public private(set) var items: [ClipboardHistoryItem]
    public let capacity: Int

    public init(capacity: Int = ClipboardHistoryStore.defaultCapacity, items: [ClipboardHistoryItem] = []) {
        self.capacity = capacity
        self.items = Self.clamped(items, capacity: capacity)
    }

    /// 入队：与最近一条相同则忽略（连按两次复制）；同内容但更早存在 → 提到最前。
    public mutating func add(_ item: ClipboardHistoryItem) {
        if let first = items.first, first.kind == item.kind,
           first.text == item.text, first.filePaths == item.filePaths {
            return
        }
        if let index = items.firstIndex(where: { $0.text == item.text && $0.kind == item.kind }) {
            var moved = items.remove(at: index)
            moved.addedAt = item.addedAt
            items.insert(moved, at: 0)
        } else {
            items.insert(item, at: 0)
        }
        items = Self.clamped(items, capacity: capacity)
    }

    public mutating func toggleFavorite(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite.toggle()
    }

    /// 展示序：收藏置顶（组内按时间倒序）。
    public var displayOrder: [ClipboardHistoryItem] {
        let favorites = items.filter(\.isFavorite)
        let rest = items.filter { !$0.isFavorite }
        return favorites + rest
    }

    private static func clamped(_ items: [ClipboardHistoryItem], capacity: Int) -> [ClipboardHistoryItem] {
        guard capacity > 0 else { return [] }
        var result = items
        if result.count > capacity {
            // 淘汰最旧的未收藏条目
            for index in stride(from: result.count - 1, through: 0, by: -1) where !result[index].isFavorite {
                result.remove(at: index)
                if result.count <= capacity { break }
            }
        }
        return result
    }
}
