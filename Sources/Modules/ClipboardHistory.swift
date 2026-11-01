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
    /// 文本内容；image/files 为摘要（image 存「图片 W×H」）。
    public let text: String
    public let imageData: Data?
    public let filePaths: [String]?
    public var addedAt: Date
    public var isFavorite: Bool
    /// 图片外置文件名（相对 App Support/clipboard_images/）；PNG 不再内联进 JSON。
    public var imageFile: String?
    /// 来源 app（frontmostApplication 启发式捕获；卡片底部展示来源图标+名称）。
    public var sourceAppName: String?
    public var sourceBundleID: String?

    public init(id: UUID = UUID(), kind: Kind, text: String, imageData: Data? = nil,
                filePaths: [String]? = nil, addedAt: Date = Date(), isFavorite: Bool = false,
                imageFile: String? = nil, sourceAppName: String? = nil,
                sourceBundleID: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.filePaths = filePaths
        self.addedAt = addedAt
        self.isFavorite = isFavorite
        self.imageFile = imageFile
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
    }

    // MARK: Codable（手写：外置后不内联 PNG，decode 全字段可选兼容旧 JSON）

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, imageData, filePaths, addedAt, isFavorite
        case imageFile, sourceAppName, sourceBundleID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        text = try c.decode(String.self, forKey: .text)
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
        filePaths = try c.decodeIfPresent([String].self, forKey: .filePaths)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        isFavorite = try c.decode(Bool.self, forKey: .isFavorite)
        imageFile = try c.decodeIfPresent(String.self, forKey: .imageFile)
        sourceAppName = try c.decodeIfPresent(String.self, forKey: .sourceAppName)
        sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(text, forKey: .text)
        try c.encode(filePaths, forKey: .filePaths)
        try c.encode(addedAt, forKey: .addedAt)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encode(imageFile, forKey: .imageFile)
        try c.encode(sourceAppName, forKey: .sourceAppName)
        try c.encode(sourceBundleID, forKey: .sourceBundleID)
        // imageData 只在未外置时编码（兜底旧数据路径）；外置后由 imageFile 承载
        if imageFile == nil {
            try c.encode(imageData, forKey: .imageData)
        }
    }
}

/// 剪贴板图片外置存储：PNG 按条目 id 落盘 App Support/clipboard_images/<uuid>.png，
/// JSON 只存文件名——避免内联 base64 把 clipboard_history.json 撑到几十 MB。
public struct ClipboardImageStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 保存图片（同 id 覆盖），返回文件名；失败返回 nil。
    @discardableResult
    public func save(id: UUID, data: Data) -> String? {
        let fileName = id.uuidString + ".png"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    /// 读取外置图片；缺失/读取失败返回 nil。
    public func load(_ fileName: String) -> Data? {
        guard Self.isValidFileName(fileName) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(fileName))
    }

    public func remove(_ fileName: String) {
        guard Self.isValidFileName(fileName) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    /// 清理孤儿图片：删除目录中不在 keeping 集合里的文件（淘汰/删除条目后调用）。
    public func purge(keeping fileNames: Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in contents where !fileNames.contains(name) && Self.isValidFileName(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// 文件名白名单：uuid.png 形态，拒绝路径穿越。
    private static func isValidFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name.hasSuffix(".png")
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

    /// 记录图片外置文件名（持久化前由 Module 调用）；条目不存在返回 false。
    @discardableResult
    public mutating func attachImageFile(id: UUID, fileName: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items[index].imageFile = fileName
        return true
    }

    /// 删除指定条目；id 不存在时静默忽略（卡片 × 删除、未知 id 防御）。
    public mutating func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
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

/// 卡片流过滤（纯逻辑，TDD）：类型 chips + 搜索框组合过滤。
/// 搜索匹配条目 text（文本内容 / 文件名摘要 / 图片「图片 W×H」摘要），大小写不敏感。
public enum ClipboardCardFilter {

    /// 过滤：kind 为 nil = 全部；searchText 纯空白视为不过滤；两者同时生效（交集）。
    public static func filter(items: [ClipboardHistoryItem], searchText: String,
                              kind: ClipboardHistoryItem.Kind?) -> [ClipboardHistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            if let kind = kind, item.kind != kind { return false }
            if query.isEmpty { return true }
            return item.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

/// 数字键码表（卡片序号热键 ⌥1~⌥9 用；键码对照 HIToolbox kVK_ANSI_*）。
public enum ClipboardDigitKeyCodes {

    /// 数字 → 键码：1=18 2=19 3=20 4=21 5=23 6=22 7=26 8=28 9=25 0=29。
    /// 0 保留在表内便于显示，但热键只注册 1~9（第 10 张卡无徽章）。
    public static let keyCodes: [Int: UInt32] = [
        1: 18, 2: 19, 3: 20, 4: 21, 5: 23,
        6: 22, 7: 26, 8: 28, 9: 25, 0: 29,
    ]

    /// 徽章文本：1 → "1"…9 → "9"；表外返回 nil（不显示徽章）。
    public static func label(for digit: Int) -> String? {
        guard keyCodes[digit] != nil, (1...9).contains(digit) else { return nil }
        return String(digit)
    }
}

/// 相对时间格式化（纯逻辑，TDD）：「刚刚 / N 分钟前 / N 小时前 / N 天前 / yyyy-MM-dd」。
/// 时区显式注入，测试用固定时区防 CI 与本地差异。
public enum RelativeTimeFormatter {

    /// to 晚于 from 的间隔分档：<60s 刚刚、<1h 分钟前、<24h 小时前、<7 天 天前，否则日期。
    /// 时钟回拨（to 早于 from）按「刚刚」处理。
    public static func label(from: Date, to: Date, timeZone: TimeZone = .current) -> String {
        let interval = to.timeIntervalSince(from)
        guard interval >= 0 else { return "刚刚" }
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 7 * 86400 { return "\(Int(interval / 86400)) 天前" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: to)
    }
}
