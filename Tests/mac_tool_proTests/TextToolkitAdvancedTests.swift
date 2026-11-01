import XCTest

/// TDD: 文本工具补全 —— 命名转换/JSON 反转义/时间戳⇄日期（对标浮引文本处理）。
final class TextToolkitAdvancedTests: XCTestCase {

    // MARK: - 命名转换

    func test_convertNaming_camel() {
        XCTAssertEqual(TextToolkitAdvanced.convertNaming("user_name_field", to: .camel), "userNameField")
        XCTAssertEqual(TextToolkitAdvanced.convertNaming("UserProfileView", to: .camel), "userProfileView")
    }

    func test_convertNaming_pascal() {
        XCTAssertEqual(TextToolkitAdvanced.convertNaming("user_name", to: .pascal), "UserName")
    }

    func test_convertNaming_snake() {
        XCTAssertEqual(TextToolkitAdvanced.convertNaming("UserProfileView", to: .snake), "user_profile_view")
        XCTAssertEqual(TextToolkitAdvanced.convertNaming("already_snake", to: .snake), "already_snake")
    }

    func test_convertNaming_kebab() {
        XCTAssertEqual(TextToolkitAdvanced.convertNaming("HTTPServer", to: .kebab), "http-server")
    }

    // MARK: - JSON 反转义

    func test_unescapeJSON_doubleEncodedString() {
        // 真实用例：日志里复制出的双层编码 JSON 字符串值
        // 目标内容: {"name": "value", "n": 1}
        let escaped = "'" + #"{"name": "value", "n": 1}"# + "'"
        // 构造双层编码：对目标内容做 JSON 字符串编码
        let encoded = String(data: try! JSONEncoder().encode(String(#"{"name": "value", "n": 1}"#)), encoding: .utf8)!
        _ = escaped
        let result = TextToolkitAdvanced.unescapeJSON(encoded)
        XCTAssertEqual(result, #"{"name": "value", "n": 1}"#)
    }

    func test_unescapeJSON_plainJSON_passthrough() {
        let plain = #"{"already": "plain"}"#
        XCTAssertEqual(TextToolkitAdvanced.unescapeJSON(plain), plain,
                       "未包裹引号的普通 JSON 不得被误改")
    }

    func test_unescapeJSON_newlineAndTab() {
        // 字符串值内的 \n \t 转义 → 解码为真实换行/制表
        let escaped = "\"line1\\nline2\\tend\""
        let result = TextToolkitAdvanced.unescapeJSON(escaped)
        XCTAssertTrue(result.contains("\n"), "应含真实换行")
        XCTAssertTrue(result.contains("\t"), "应含真实制表")
    }

    // MARK: - 时间戳⇄日期

    func test_convertTimestamps_secondsToDateTime() {
        // 2026-11-01 00:00:00 UTC = 1798588800
        let date = Date(timeIntervalSince1970: 1_798_588_800)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        let expected = f.string(from: date)
        let (output, skipped) = TextToolkitAdvanced.convertTimestamps(
            "1798588800", direction: .toDateTime)
        XCTAssertEqual(output, expected)
        XCTAssertEqual(skipped, 0)
    }

    func test_convertTimestamps_millisRecognized() {
        let millis = "1798588800000"
        let (output, skipped) = TextToolkitAdvanced.convertTimestamps(millis, direction: .toDateTime)
        XCTAssertFalse(output.isEmpty)
        XCTAssertEqual(skipped, 0, "13 位毫秒应识别")
    }

    func test_convertTimestamps_datetimeToMillis() throws {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        let date = try XCTUnwrap(f.date(from: "2026-11-01 08:00:00"))
        let expectedMillis = String(Int64(date.timeIntervalSince1970 * 1000))
        let (output, skipped) = TextToolkitAdvanced.convertTimestamps(
            "2026-11-01 08:00:00", direction: .toMillis)
        XCTAssertEqual(output, expectedMillis)
        XCTAssertEqual(skipped, 0)
    }

    func test_convertTimestamps_mixedLines_partialSkip() {
        let (output, skipped) = TextToolkitAdvanced.convertTimestamps(
            "1798588800\n不是时间戳\n2026-11-01 08:00:00", direction: .toMillis)
        XCTAssertEqual(skipped, 1, "1 行秒时间戳无法按日期解析应跳过计数")
        XCTAssertTrue(output.contains("不是时间戳"))
    }
}
