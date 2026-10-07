import Foundation
import CryptoKit

/// 暂存条目类型:文件引用 / 选中文本 / 图片(PNG)/ 链接。
/// 旧版持久化 JSON 没有 kind 字段,解码时缺省为 .file(向后兼容)。
public enum TransferItemKind: String, Codable, Equatable, CaseIterable {
    case file
    case text
    case image
    case link

    /// 是否需要文件存在性检查(只有文件引用可能因文件被移走而失效)。
    public var requiresFileExistenceCheck: Bool { self == .file }
}

/// 合成去重键:非 file 条目没有天然唯一 URL,用内容哈希合成稳定 URL,
/// 让 store 的按 URL 去重逻辑对 text/image 同样生效。
public enum TransferItemSyntheticURL {

    /// 内容 SHA-256 前 16 字节的十六进制串(碰撞概率可忽略,长度可控)。
    static func digestHex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// text 条目的合成 URL:transfer-shelf://text/<内容哈希>
    public static func textURL(content: String) -> URL {
        URL(string: "transfer-shelf://text/\(digestHex(for: Data(content.utf8)))")!
    }

    /// image 条目的合成 URL:transfer-shelf://image/<PNG 数据哈希>
    public static func imageURL(pngData: Data) -> URL {
        URL(string: "transfer-shelf://image/\(digestHex(for: pngData))")!
    }
}
