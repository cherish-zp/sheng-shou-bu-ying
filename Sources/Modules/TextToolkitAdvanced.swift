import Foundation
import CryptoKit

/// 文本工具集补全（TDD，对标浮引文本处理）：命名转换、JSON 反转义、时间戳⇄日期。
public enum TextToolkitAdvanced {

    // MARK: - 命名转换

    public enum NamingCase: String, CaseIterable {
        case camel = "小驼峰"
        case pascal = "大驼峰"
        case snake = "下划线"
        case kebab = "短横线"
    }

    /// 任意输入 → 单词数组。缩写段拆分：HTTPServer → HTTP/Server
    /// （大写后跟小写 = 段末；小写后跟大写 = 段界）。
    static func words(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            if !ch.isLetter && !ch.isNumber {
                if !current.isEmpty { tokens.append(current); current = "" }
                continue
            }
            if ch.isUppercase, !current.isEmpty,
               let last = current.last, last.isLowercase {
                tokens.append(current); current = String(ch)
                continue
            }
            // 大写段结束：下一个是小写（HTTP|Server）
            if ch.isUppercase, current.count > 1,
               let last = current.last, last.isUppercase,
               i + 1 < chars.count, chars[i + 1].isLowercase {
                tokens.append(current); current = String(ch)
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens.map { $0.lowercased() }.filter { !$0.isEmpty }
    }

    public static func convertNaming(_ text: String, to target: NamingCase) -> String {
        let parts = words(text)
        switch target {
        case .camel:
            return parts.enumerated().map { i, w in i == 0 ? w : w.prefix(1).uppercased() + w.dropFirst() }.joined()
        case .pascal:
            return parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        case .snake:
            return parts.joined(separator: "_")
        case .kebab:
            return parts.joined(separator: "-")
        }
    }

    // MARK: - JSON 反转义

    /// JSON 字符串反转义：输入是被引号包裹的 JSON 字符串值（如日志里复制的
    /// "{\"a\":1}"），解码为真实内容。未包裹引号的普通 JSON 原样返回（幂等安全）。
    public static func unescapeJSON(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2,
              let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data),
              decoded != trimmed else { return text }
        return decoded
    }

    // MARK: - 时间戳 ⇄ 日期

    public enum TimestampDirection: String, CaseIterable {
        case toDateTime = "时间戳转时间"
        case toMillis = "时间转毫秒时间戳"
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    /// 逐行转换：识别 10/13 位时间戳或 "yyyy-MM-dd HH:mm:ss" 日期，无法识别的行原样保留。
    /// 返回 (转换结果, 无法识别的行数)。
    public static func convertTimestamps(_ text: String, direction: TimestampDirection) -> (output: String, skipped: Int) {
        var skipped = 0
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            switch direction {
            case .toDateTime:
                if let seconds = Int64(trimmed) {
                    if String(seconds).count == 13 {  // 毫秒
                        let date = Date(timeIntervalSince1970: Double(seconds) / 1000)
                        return formatter.string(from: date)
                    }
                    if String(seconds).count == 10 {
                        let date = Date(timeIntervalSince1970: Double(seconds))
                        return formatter.string(from: date)
                    }
                }
                skipped += 1
                return String(line)
            case .toMillis:
                if let date = formatter.date(from: trimmed) {
                    return String(Int64(date.timeIntervalSince1970 * 1000))
                }
                // 已是纯秒数字（10 位）：直通 ×1000 为毫秒
                if let seconds = Int64(trimmed), trimmed.count == 10 {
                    return String(seconds * 1000)
                }
                skipped += 1
                return String(line)
            }
        }
        return (lines.joined(separator: "\n"), skipped)
    }
}
