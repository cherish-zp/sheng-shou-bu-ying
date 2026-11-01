import AppKit
import Foundation
import ImageIO

/// 剪贴板图片条目的缩略图与行高度量（纯逻辑，TDD）。
/// 图片条目此前只渲染「图片 W×H」文字、行高压在 34pt——用户看不到图片实际内容。
/// 卡片式布局：缩略图宽度撑满条目、高度按图片宽高比，超宽/超高夹在上下限内。
public enum ClipboardThumbnail {

    /// 小图缩略图长边上限（pt），小图不放大。
    public static let maxThumbnailPixel: CGFloat = 72
    /// 卡片缩略图高度上限（pt）：竖长图不至于占满整窗。
    public static let maxThumbnailHeight: CGFloat = 140
    /// 卡片缩略图高度下限（pt）：超宽图不至于一条线看不清。
    public static let minThumbnailHeight: CGFloat = 44
    /// 图片行内左右留白。
    public static let imageRowHorizontalInset: CGFloat = 8
    /// 缩略图下方文字带（间距 4 + 文字 18 + 底部 8）。
    public static let imageRowTextBand: CGFloat = 30
    /// 图片行上下留白。
    public static let imageRowVerticalInset: CGFloat = 8

    /// PNG data → NSImage（用于渲染）；解码失败返回 nil。
    public static func make(fromPNG data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return NSImage(cgImage: decoded,
                       size: NSSize(width: decoded.width, height: decoded.height))
    }

    /// 卡片缩略图尺寸：宽度撑满可用宽度，高度按图片宽高比夹在 [min, max]；
    /// 未知尺寸按方图（1:1）处理。
    public static func thumbnailSize(pixelWidth: CGFloat, pixelHeight: CGFloat,
                                     availableWidth: CGFloat) -> NSSize {
        let width = max(availableWidth, 1)
        guard pixelWidth > 0, pixelHeight > 0 else {
            return NSSize(width: width, height: min(width, maxThumbnailHeight))
        }
        let height = min(max(width * pixelHeight / pixelWidth, minThumbnailHeight), maxThumbnailHeight)
        return NSSize(width: width, height: height)
    }

    /// 行高：图片行 = 缩略图高 + 文字带 + 上下留白；其余紧凑 34pt。
    public static func rowHeight(for kind: ClipboardHistoryItem.Kind,
                                 pixelWidth: CGFloat = 0, pixelHeight: CGFloat = 0,
                                 availableWidth: CGFloat = 0) -> CGFloat {
        guard kind == .image else { return 34 }
        return thumbnailSize(pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                             availableWidth: availableWidth).height
            + imageRowTextBand + imageRowVerticalInset * 2
    }
}

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
