import XCTest
import CoreGraphics
import CryptoKit

/// TDD: 文本工具集 —— JSON 校验/美化、哈希、Base64/URL、文本变换。
final class TextToolkitTests: XCTestCase {

    // MARK: - JSON

    func test_jsonValid() {
        let result = TextToolkit.validateJSON(#"{"a": 1, "b": [true, null]}"#)
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.errorMessage)
    }

    func test_jsonInvalid_reportsError() {
        let result = TextToolkit.validateJSON(#"{"a": 1,,"#)
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func test_jsonFragmentsAllowed() {
        XCTAssertTrue(TextToolkit.validateJSON("123").isValid)
        XCTAssertTrue(TextToolkit.validateJSON(#""just a string""#).isValid)
    }

    func test_prettyJSON_sortsAndIndents() throws {
        let pretty = try XCTUnwrap(TextToolkit.prettyJSON(#"{"b":1,"a":2}"#))
        XCTAssertTrue(pretty.contains("\n"), "应有多行缩进")
        let keyA = try XCTUnwrap(pretty.range(of: #""a""#)).lowerBound
        let keyB = try XCTUnwrap(pretty.range(of: #""b""#)).lowerBound
        XCTAssertLessThan(keyA, keyB, "键应排序")
    }

    func test_prettyJSON_invalidReturnsNil() {
        XCTAssertNil(TextToolkit.prettyJSON("not-json"))
    }

    // MARK: - 哈希

    func test_md5KnownVector() {
        // RFC 1321 标准向量
        XCTAssertEqual(TextToolkit.md5(""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(TextToolkit.md5("abc"), "900150983cd24fb0d6963f7d28e17f72")
    }

    func test_sha256KnownVector() {
        XCTAssertEqual(TextToolkit.sha256("abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func test_sha1KnownVector() {
        XCTAssertEqual(TextToolkit.sha1("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
    }

    // MARK: - Base64 / URL

    func test_base64RoundTrip() {
        let encoded = TextToolkit.base64Encode("圣手捕影 hello")
        XCTAssertEqual(TextToolkit.base64Decode(encoded), "圣手捕影 hello")
    }

    func test_base64Decode_garbageReturnsNil() {
        XCTAssertNil(TextToolkit.base64Decode("!!!not-base64!!!"))
    }

    func test_urlEncodeReservesUnreserved() {
        XCTAssertEqual(TextToolkit.urlEncode("a b/c"), "a%20b%2Fc")
        XCTAssertEqual(TextToolkit.urlEncode("a-b._~"), "a-b._~", "RFC 3986 非保留字符不转义")
    }

    func test_urlDecodeRoundTrip() {
        XCTAssertEqual(TextToolkit.urlDecode("a%20b%2Fc"), "a b/c")
        XCTAssertEqual(TextToolkit.urlDecode(TextToolkit.urlEncode("中文")), "中文")
    }

    // MARK: - 文本变换

    func test_removeBlankLines() {
        XCTAssertEqual(TextToolkit.removeBlankLines("a\n\n  \nb\n"), "a\nb")
    }

    func test_removeDuplicateLines_keepsFirstOccurrenceOrder() {
        XCTAssertEqual(TextToolkit.removeDuplicateLines("b\na\nb\nc\na"), "b\na\nc")
    }

    func test_sortLines() {
        XCTAssertEqual(TextToolkit.sortLines("c\na\nb"), "a\nb\nc")
    }

    func test_lineStats() {
        let stats = TextToolkit.lineStats("ab\ncd")
        XCTAssertEqual(stats.lines, 2)
        XCTAssertEqual(stats.characters, 5)
        XCTAssertEqual(stats.bytes, 5)
    }
}
