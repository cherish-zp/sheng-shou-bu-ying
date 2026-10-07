import Foundation
import AppKit

/// 暂存内容载荷上限与拒绝文案(纯逻辑):文本 100KB、图片 PNG 5MB。
public enum TransferItemPayload {
    /// 文本上限:100_000 UTF-8 字节(按字节而非字符计,贴近「100KB」语义)。
    public static let maxTextUTF8Bytes = 100_000
    /// 单张图片 PNG 上限:5_000_000 字节。
    public static let maxImagePNGBytes = 5_000_000

    public static let textTooLongMessage = "文本过长，上限 100KB"
    public static let imageTooLargeMessage = "图片过大，单张上限 5MB"

    public static func isValidText(_ text: String) -> Bool {
        text.utf8.count <= maxTextUTF8Bytes
    }

    public static func isValidImagePNG(_ pngData: Data) -> Bool {
        pngData.count <= maxImagePNGBytes
    }
}

/// intake 结果:入列条目 + 被拒载荷的提示文案(混合批次里合法条目照常入列)。
public struct TransferIntakeResult: Equatable {
    public let items: [TransferItem]
    public let rejectionMessage: String?

    public init(items: [TransferItem], rejectionMessage: String? = nil) {
        self.items = items
        self.rejectionMessage = rejectionMessage
    }
}

/// 拖入/粘贴板 → 条目的解析器。
/// 优先级:fileURL > 图片(PNG) > 链接(.URL) > 文本(.string)——
/// Finder/浏览器拖链接时 pasteboard 同时带 .URL 与 .string,链接必须先于文本判定。
/// 纯函数入口只接收抽好的载荷,便于单测;NSPasteboard 桥接(tiff→PNG 等)在 from(_:)。
public enum TransferItemKindIntake {

    /// 纯函数:载荷 → 条目 + 拒绝提示。
    public static func result(fileURLs: [URL], pngData: Data?, text: String?, urlStrings: [String]) -> TransferIntakeResult {
        var items: [TransferItem] = []
        var rejection: String?

        if !fileURLs.isEmpty {
            items.append(contentsOf: fileURLs.map { TransferItem(url: $0) })
        } else if let pngData = pngData {
            if TransferItemPayload.isValidImagePNG(pngData) {
                items.append(TransferItem.image(pngData))
            } else {
                rejection = TransferItemPayload.imageTooLargeMessage
            }
        } else if !urlStrings.isEmpty {
            let links = urlStrings.compactMap { URL(string: $0) }.filter { $0.host != nil || $0.isFileURL }
            items.append(contentsOf: links.map { TransferItem.link($0) })
        } else if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            if TransferItemPayload.isValidText(text) {
                items.append(TransferItem.text(text))
            } else {
                rejection = TransferItemPayload.textTooLongMessage
            }
        }

        return TransferIntakeResult(items: items, rejectionMessage: rejection)
    }

    /// AppKit 桥接:从 pasteboard(拖拽或通用剪贴板)抽取载荷后走纯函数。
    public static func result(from pasteboard: NSPasteboard) -> TransferIntakeResult {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        let fileURLs = urls.filter { $0.isFileURL }
        let linkURLs = urls.filter { !$0.isFileURL }.map(\.absoluteString)
        let text = pasteboard.string(forType: .string)
        // 桥接只负责抽原始载荷;link/text 的取舍(含 text 是否恰好等于链接)交给纯函数优先级。
        return result(
            fileURLs: fileURLs,
            pngData: pngData(from: pasteboard),
            text: text,
            urlStrings: linkURLs
        )
    }

    /// 图片载荷:优先 .png;.tiff 转 PNG(浏览器/Finder 拖图常见 tiff 表示)。
    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
