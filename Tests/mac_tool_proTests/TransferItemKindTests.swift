import XCTest
import Foundation

/// TDD: 条目类型扩展(kind)。
/// 1) 旧版 JSON(无 kind 字段)解码后必须落到 .file,向后兼容;
/// 2) 新版 JSON 携带 kind/text/imageData/link,roundtrip 不丢;
/// 3) 非 file 条目的合成 URL 稳定(同内容去重、异内容区分);
/// 4) purge 对非 file kind 跳过 fileExists(永不过期)。
final class TransferItemKindTests: XCTestCase {

    // MARK: - 旧版 JSON 向后兼容

    func test_legacyJSONWithoutKindDecodesAsFile() throws {
        // 第一棒产出的旧格式:id/url/name/addedAt,没有 kind。
        let legacy = """
        [{"id":"11111111-2222-3333-4444-555555555555","url":"file:///tmp/a.txt","name":"a.txt","addedAt":"2026-10-06T00:00:00Z"}]
        """
        let data = try XCTUnwrap(legacy.data(using: .utf8))
        let store = try XCTUnwrap(TransferShelfStore.load(from: data))
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.kind, .file, "旧 JSON 缺 kind 字段必须默认为 .file")
        XCTAssertEqual(store.items.first?.name, "a.txt")
        XCTAssertEqual(store.items.first?.url.path, "/tmp/a.txt")
    }

    func test_legacyRoundtripKeepsFileKind() throws {
        var store = TransferShelfStore()
        store.add(url: URL(fileURLWithPath: "/tmp/legacy.txt"))
        let data = try XCTUnwrap(store.encode())
        let restored = try XCTUnwrap(TransferShelfStore.load(from: data))
        XCTAssertEqual(restored.items.first?.kind, .file)
        XCTAssertEqual(restored.items.first?.url.path, "/tmp/legacy.txt")
    }

    // MARK: - 新格式 roundtrip

    func test_textItemRoundtrip() throws {
        var store = TransferShelfStore()
        store.add(item: TransferItem.text("一段选中的文本"))
        let data = try XCTUnwrap(store.encode())
        let restored = try XCTUnwrap(TransferShelfStore.load(from: data))
        XCTAssertEqual(restored.items.first?.kind, .text)
        XCTAssertEqual(restored.items.first?.text, "一段选中的文本")
        XCTAssertNil(restored.items.first?.imageData)
        XCTAssertNil(restored.items.first?.link)
    }

    func test_imageItemRoundtrip() throws {
        var store = TransferShelfStore()
        store.add(item: TransferItem.image(Data([0x89, 0x50, 0x4E, 0x47])))
        let data = try XCTUnwrap(store.encode())
        let restored = try XCTUnwrap(TransferShelfStore.load(from: data))
        XCTAssertEqual(restored.items.first?.kind, .image)
        XCTAssertEqual(restored.items.first?.imageData, Data([0x89, 0x50, 0x4E, 0x47]),
                       "imageData 必须以 Base64 进 JSON 并无损还原")
    }

    func test_linkItemRoundtrip() throws {
        var store = TransferShelfStore()
        store.add(item: TransferItem.link(URL(string: "https://example.com/a")!))
        let data = try XCTUnwrap(store.encode())
        let restored = try XCTUnwrap(TransferShelfStore.load(from: data))
        XCTAssertEqual(restored.items.first?.kind, .link)
        XCTAssertEqual(restored.items.first?.link?.absoluteString, "https://example.com/a")
    }

    func test_mixedKindsRoundtripKeepsOrder() throws {
        var store = TransferShelfStore()
        store.add(url: URL(fileURLWithPath: "/tmp/f.txt"))
        store.add(item: TransferItem.text("hello"))
        store.add(item: TransferItem.image(Data([0x01])))
        store.add(item: TransferItem.link(URL(string: "https://e.com")!))
        let data = try XCTUnwrap(store.encode())
        let restored = try XCTUnwrap(TransferShelfStore.load(from: data))
        XCTAssertEqual(restored.items.map(\.kind), [.file, .text, .image, .link])
    }

    // MARK: - 合成 URL(去重键)

    func test_textItemSyntheticURLStableForSameContent() {
        let a = TransferItem.text("同一段文本")
        let b = TransferItem.text("同一段文本")
        XCTAssertEqual(a.url, b.url, "同内容文本的合成 URL 必须一致,使 store 按 URL 去重生效")
        XCTAssertNotEqual(a.id, b.id)
    }

    func test_textItemSyntheticURLDiffersForDifferentContent() {
        XCTAssertNotEqual(
            TransferItem.text("文本甲").url,
            TransferItem.text("文本乙").url
        )
    }

    func test_imageItemSyntheticURLStableForSamePNG() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        XCTAssertEqual(
            TransferItem.image(png).url,
            TransferItem.image(png).url,
            "同 PNG 数据的合成 URL 必须一致"
        )
    }

    func test_linkItemUsesLinkURLAsDedupKey() {
        let url = URL(string: "https://example.com/x")!
        XCTAssertEqual(TransferItem.link(url).url, url, "link 条目直接用链接 URL 作为去重键")
    }

    func test_textItemNameIsFirstLineSummary() {
        let item = TransferItem.text("第一行摘要\n第二行\n第三行")
        XCTAssertEqual(item.name, "第一行摘要", "text 条目名称取首行摘要")
    }

    func test_textItemNameTruncatedForLongLine() {
        let long = String(repeating: "长", count: 200)
        let item = TransferItem.text(long)
        XCTAssertLessThanOrEqual(item.name.count, 80, "长首行必须截断,避免 JSON 膨胀与展示溢出")
    }

    func test_linkItemNameIsHostAndPath() {
        let item = TransferItem.link(URL(string: "https://docs.example.com/guide/intro")!)
        XCTAssertEqual(item.name, "docs.example.com/guide/intro")
    }

    func test_imageItemNameIsPlaceholder() {
        XCTAssertEqual(TransferItem.image(Data([0x01])).name, "图片")
    }

    // MARK: - store.add(item:)

    func test_addItemRespectsMaxCount() {
        var store = TransferShelfStore(maxCount: 2)
        store.add(item: TransferItem.text("1"))
        store.add(item: TransferItem.text("2"))
        store.add(item: TransferItem.text("3"))
        XCTAssertEqual(store.items.count, 2, "非 file 条目同样受 maxCount 上限约束(淘汰最旧)")
        XCTAssertEqual(store.items.map(\.text), ["2", "3"])
    }

    func test_addItemDedupesBySyntheticURL() {
        var store = TransferShelfStore()
        XCTAssertNotNil(store.add(item: TransferItem.text("重复内容")))
        XCTAssertNil(store.add(item: TransferItem.text("重复内容")), "同内容文本再次入列应命中去重")
        XCTAssertEqual(store.items.count, 1)
    }

    func test_addFileURLStillWorks() {
        var store = TransferShelfStore()
        let url = URL(fileURLWithPath: "/tmp/x.txt")
        let item = store.add(url: url)
        XCTAssertEqual(item?.kind, .file, "add(url:) 产出的条目 kind 必须是 .file")
    }

    // MARK: - purge 跳过非 file kind

    func test_purgeInvalidKeepsNonFileItemsEvenWhenFileExistsFalse() {
        var store = TransferShelfStore()
        store.add(url: URL(fileURLWithPath: "/tmp/gone.txt"))
        store.add(item: TransferItem.text("文本不过期"))
        store.add(item: TransferItem.link(URL(string: "https://e.com")!))
        store.add(item: TransferItem.image(Data([0x07])))

        let removed = store.purgeInvalid(fileExists: { _ in false })

        XCTAssertEqual(removed.map(\.kind), [.file], "只有 file 条目可能失效被 purge")
        XCTAssertEqual(store.items.map(\.kind), [.text, .link, .image],
                       "非 file 条目不检查文件存在性,永不因 fileExists=false 被移除")
    }

    func test_purgeInvalidStillRemovesMissingFiles() {
        var store = TransferShelfStore()
        store.add(url: URL(fileURLWithPath: "/tmp/here.txt"))
        store.add(url: URL(fileURLWithPath: "/tmp/gone.txt"))
        let removed = store.purgeInvalid(fileExists: { $0.path == "/tmp/here.txt" })
        XCTAssertEqual(removed.map(\.url.path), ["/tmp/gone.txt"])
        XCTAssertEqual(store.items.map(\.url.path), ["/tmp/here.txt"])
    }

    func test_isValidSkipsFileCheckForNonFileKinds() {
        let store = TransferShelfStore()
        let textItem = TransferItem.text("hi")
        XCTAssertTrue(store.isValid(textItem, fileExists: { _ in false }),
                      "非 file 条目 isValid 不应依赖文件系统")
    }
}
