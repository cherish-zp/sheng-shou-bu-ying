import Foundation
import CryptoKit

/// 文本工具集纯逻辑（TDD）：JSON 校验、哈希、Base64/URL 编解码、常用文本变换。
/// 全部纯函数；失败显式返回，不抛异常。
public enum TextToolkit {

    // MARK: - JSON 校验

    public struct JSONValidation: Equatable {
        public let isValid: Bool
        /// 非法时的错误描述（合法为 nil）。
        public let errorMessage: String?
    }

    public static func validateJSON(_ text: String) -> JSONValidation {
        guard let data = text.data(using: .utf8) else {
            return JSONValidation(isValid: false, errorMessage: "无法按 UTF-8 编码")
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return JSONValidation(isValid: true, errorMessage: nil)
        } catch {
            return JSONValidation(isValid: false, errorMessage: error.localizedDescription)
        }
    }

    /// JSON 美化（2 空格缩进）；非法输入返回 nil。
    public static func prettyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: pretty, encoding: .utf8)
    }

    // MARK: - 哈希

    public static func md5(_ text: String) -> String {
        digest(text) { CryptoKit.Insecure.MD5.hash(data: $0) }
    }

    public static func sha1(_ text: String) -> String {
        digest(text) { CryptoKit.Insecure.SHA1.hash(data: $0) }
    }

    public static func sha256(_ text: String) -> String {
        digest(text) { CryptoKit.SHA256.hash(data: $0) }
    }

    private static func digest<D: Sequence>(_ text: String, using make: (Data) -> D) -> String where D.Element == CryptoKit.Insecure.SHA1.Digest.Element {
        let digest = make(Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Base64 / URL

    public static func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    public static func base64Decode(_ text: String) -> String? {
        guard let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func urlEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    public static func urlDecode(_ text: String) -> String? {
        text.removingPercentEncoding
    }

    // MARK: - 文本变换

    public static func removeBlankLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    public static func removeDuplicateLines(_ text: String) -> String {
        var seen = Set<String>()
        var result: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if seen.insert(String(line)).inserted { result.append(String(line)) }
        }
        return result.joined(separator: "\n")
    }

    public static func sortLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).sorted().joined(separator: "\n")
    }

    public static func lineStats(_ text: String) -> (lines: Int, characters: Int, bytes: Int) {
        (text.split(separator: "\n", omittingEmptySubsequences: false).count,
         text.count, text.utf8.count)
    }
}
