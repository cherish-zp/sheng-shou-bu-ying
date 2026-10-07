import XCTest
import Foundation
import AppKit

/// TDD: 非文件内容捕获的载荷校验与 intake 解析。
/// 1) TransferItemPayload 上限:文本 100KB(UTF-8 字节)、图片 PNG 5MB,边界含等号;
/// 2) TransferItemKindIntake 纯函数:file > image > link > text 优先级、超限拒绝文案;
/// 3) NSPasteboard 桥接:tiff→PNG、.URL 识别为 link、纯文本识别为 text。
final class TransferItemKindIntakeTests: XCTestCase {

    // MARK: - TransferItemPayload 上限

    func test_textWithinLimitIsValid() {
        XCTAssertTrue(TransferItemPayload.isValidText(String(repeating: "a", count: 100_000)),
                      "100KB(含)以内允许")
        XCTAssertFalse(TransferItemPayload.isValidText(String(repeating: "a", count: 100_001)),
                       "超出 100KB 拒绝")
        XCTAssertTrue(TransferItemPayload.isValidText("短文本"))
    }

    func test_textLimitCountsUTF8BytesNotCharacters() {
        // "é" 是 2 字节 UTF-8:50_000 个 = 100_000 字节,应在限内(字符数只有 5 万)。
        XCTAssertTrue(TransferItemPayload.isValidText(String(repeating: "é", count: 50_000)))
        XCTAssertFalse(TransferItemPayload.isValidText(String(repeating: "é", count: 50_001)))
    }

    func test_imageWithinLimitIsValid() {
        XCTAssertTrue(TransferItemPayload.isValidImagePNG(Data(count: 5_000_000)),
                      "5MB(含)以内允许")
        XCTAssertFalse(TransferItemPayload.isValidImagePNG(Data(count: 5_000_001)),
                       "超出 5MB 拒绝")
    }

    func test_rejectionMessages() {
        XCTAssertEqual(TransferItemPayload.textTooLongMessage, "文本过长，上限 100KB")
        XCTAssertEqual(TransferItemPayload.imageTooLargeMessage, "图片过大，单张上限 5MB")
    }

    // MARK: - intake 纯函数:优先级

    func test_fileURLsTakePriority() {
        let result = TransferItemKindIntake.result(
            fileURLs: [URL(fileURLWithPath: "/tmp/a.pdf")],
            pngData: Data([0x01]),
            text: "ignored",
            urlStrings: ["https://ignored.com"]
        )
        XCTAssertEqual(result.items.map(\.kind), [.file])
        XCTAssertNil(result.rejectionMessage)
    }

    func test_imageBeforeLinkAndText() {
        let result = TransferItemKindIntake.result(
            fileURLs: [], pngData: Data([0x89, 0x50]),
            text: "ignored", urlStrings: ["https://ignored.com"]
        )
        XCTAssertEqual(result.items.map(\.kind), [.image])
    }

    func test_linkBeforeText() {
        let result = TransferItemKindIntake.result(
            fileURLs: [], pngData: nil, text: "some text",
            urlStrings: ["https://example.com/page"]
        )
        XCTAssertEqual(result.items.map(\.kind), [.link])
        XCTAssertEqual(result.items.first?.link?.absoluteString, "https://example.com/page")
    }

    func test_plainTextBecomesTextItem() {
        let result = TransferItemKindIntake.result(
            fileURLs: [], pngData: nil, text: "一段选中的文字", urlStrings: []
        )
        XCTAssertEqual(result.items.map(\.kind), [.text])
        XCTAssertEqual(result.items.first?.text, "一段选中的文字")
    }

    func test_multipleFileURLsProduceMultipleItems() {
        let urls = [URL(fileURLWithPath: "/tmp/1.txt"), URL(fileURLWithPath: "/tmp/2.txt")]
        let result = TransferItemKindIntake.result(
            fileURLs: urls, pngData: nil, text: nil, urlStrings: []
        )
        XCTAssertEqual(result.items.map(\.url), urls)
    }

    func test_multipleLinkURLsProduceMultipleItems() {
        let result = TransferItemKindIntake.result(
            fileURLs: [], pngData: nil, text: nil,
            urlStrings: ["https://a.com", "https://b.com"]
        )
        XCTAssertEqual(result.items.map(\.link?.absoluteString), ["https://a.com", "https://b.com"])
    }

    func test_emptyPayloadProducesNothing() {
        let result = TransferItemKindIntake.result(
            fileURLs: [], pngData: nil, text: nil, urlStrings: []
        )
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNil(result.rejectionMessage)
    }

    func test_whitespaceOnlyTextProducesNothing() {
        let result = TransferItemKindIntake.result(
            fileURLs: [], pngData: nil, text: "   \n  ", urlStrings: []
        )
        XCTAssertTrue(result.items.isEmpty, "纯空白文本不入列")
        XCTAssertNil(result.rejectionMessage)
    }

    // MARK: - intake 纯函数:超限拒绝

    func test_oversizedTextRejectedWithMessage() {
        let huge = String(repeating: "a", count: 100_001)
        let result = TransferItemKindIntake.result(
            fileURLs: [], pngData: nil, text: huge, urlStrings: []
        )
        XCTAssertTrue(result.items.isEmpty, "超限文本不得入列")
        XCTAssertEqual(result.rejectionMessage, "文本过长，上限 100KB")
    }

    func test_oversizedImageRejectedWithMessage() {
        let huge = Data(count: 5_000_001)
        let result = TransferItemKindIntake.result(
            fileURLs: [], pngData: huge, text: nil, urlStrings: []
        )
        XCTAssertTrue(result.items.isEmpty, "超限图片不得入列")
        XCTAssertEqual(result.rejectionMessage, "图片过大，单张上限 5MB")
    }

    func test_mixedBatchFilePrioritySwallowsOtherPayloads() {
        // Finder 拖文件时 pasteboard 自带路径 string,因此 file 优先分支必须
        // 整体吞掉其余载荷(不额外入列路径文本,也不误报超限)。
        let url = URL(fileURLWithPath: "/tmp/ok.txt")
        let result = TransferItemKindIntake.result(
            fileURLs: [url], pngData: Data([0x01]),
            text: String(repeating: "a", count: 100_001), urlStrings: ["https://x.com"]
        )
        XCTAssertEqual(result.items.map(\.url), [url], "file 优先,其余载荷不入列")
        XCTAssertNil(result.rejectionMessage)
    }

    // MARK: - NSPasteboard 桥接

    func test_pasteboardFileURL() throws {
        let board = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("intake-\(UUID().uuidString)")))
        board.declareTypes([.fileURL], owner: nil)
        board.setString(URL(fileURLWithPath: "/tmp/pb.txt").absoluteString, forType: .fileURL)

        let result = TransferItemKindIntake.result(from: board)
        XCTAssertEqual(result.items.map(\.kind), [.file])
        XCTAssertEqual(result.items.first?.url.path, "/tmp/pb.txt")
    }

    func test_pasteboardPlainText() throws {
        let board = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("intake-\(UUID().uuidString)")))
        board.declareTypes([.string], owner: nil)
        board.setString("剪贴板里的文字", forType: .string)

        let result = TransferItemKindIntake.result(from: board)
        XCTAssertEqual(result.items.map(\.kind), [.text])
        XCTAssertEqual(result.items.first?.text, "剪贴板里的文字")
    }

    func test_pasteboardURLIsLink() throws {
        let board = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("intake-\(UUID().uuidString)")))
        board.declareTypes([.URL, .string], owner: nil)
        board.setString("https://example.com/doc", forType: .URL)
        board.setString("https://example.com/doc", forType: .string)

        let result = TransferItemKindIntake.result(from: board)
        XCTAssertEqual(result.items.map(\.kind), [.link], "拖链接时 .URL 类型优先于 .string")
    }

    func test_pasteboardTIFFIsConvertedToPNG() throws {
        // 生成一张 4×4 红色 TIFF
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 16, bitsPerPixel: 32)
        rep?.setColor(NSColor.red, atX: 0, y: 0)
        let tiff = try XCTUnwrap(rep?.tiffRepresentation)
        let board = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("intake-\(UUID().uuidString)")))
        board.declareTypes([.tiff], owner: nil)
        board.setData(tiff, forType: .tiff)

        let result = TransferItemKindIntake.result(from: board)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.kind, .image)
        let png = try XCTUnwrap(result.items.first?.imageData)
        XCTAssertEqual(png.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]), "tiff 必须转成 PNG 存储")
        XCTAssertNotNil(NSImage(data: png), "转换产物应是合法图片")
    }

    func test_pasteboardPNGStaysPNG() throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 8, bitsPerPixel: 32)
        let png = try XCTUnwrap(rep?.representation(using: .png, properties: [:]))
        let board = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("intake-\(UUID().uuidString)")))
        board.declareTypes([.png], owner: nil)
        board.setData(png, forType: .png)

        let result = TransferItemKindIntake.result(from: board)
        XCTAssertEqual(result.items.first?.imageData, png, "PNG 载荷原样入列")
    }

    func test_pasteboardEmptyProducesNothing() throws {
        let board = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("intake-\(UUID().uuidString)")))
        board.clearContents()
        let result = TransferItemKindIntake.result(from: board)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNil(result.rejectionMessage)
    }
}
