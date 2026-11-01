import XCTest

/// TDD: 剪贴板图片外置存储与来源 app 记录。
/// 此前图片 PNG 内联在 clipboard_history.json（单图可达 2MB，JSON 膨胀到几十 MB）；
/// 来源 app 未记录（浮引卡片底部有来源 app 图标）。
final class ClipboardImageStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipImgStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() -> ClipboardImageStore {
        ClipboardImageStore(directory: tempDir)
    }

    private func pngData(seed: UInt8) -> Data {
        var bytes = [UInt8](repeating: seed, count: 64)
        bytes[0] = 0x89; bytes[1] = 0x50   // PNG 魔数开头（存储层不校验内容，仅示意）
        return Data(bytes)
    }

    // MARK: - 存取

    func test_save_load_roundTrip() {
        let store = makeStore()
        let id = UUID()
        let fileName = store.save(id: id, data: pngData(seed: 1))
        XCTAssertNotNil(fileName)
        XCTAssertEqual(store.load(fileName!), pngData(seed: 1), "外置图片必须可读回")
    }

    func test_save_overwritesSameID() {
        let store = makeStore()
        let id = UUID()
        _ = store.save(id: id, data: pngData(seed: 1))
        let again = store.save(id: id, data: pngData(seed: 2))
        XCTAssertEqual(store.load(again!), pngData(seed: 2), "同 id 重复保存覆盖旧图")
    }

    // MARK: - 清理

    func test_purge_removesOrphansKeepsReferenced() {
        let store = makeStore()
        let keptName = store.save(id: UUID(), data: pngData(seed: 1))!
        let orphanName = store.save(id: UUID(), data: pngData(seed: 2))!
        store.purge(keeping: [keptName])
        XCTAssertNotNil(store.load(keptName), "被引用的图片不得清理")
        XCTAssertNil(store.load(orphanName), "孤儿图片必须清理")
    }

    func test_purge_ignoresPathTraversalNames() {
        let store = makeStore()
        // 恶意/异常文件名不得让 purge 删到目录外
        store.purge(keeping: ["../escape.png"])
        XCTAssertNotNil(store.load(store.save(id: UUID(), data: pngData(seed: 3))!))
    }

    // MARK: - 模型字段兼容

    func test_itemCodable_imageFileRoundTrip() throws {
        let item = ClipboardHistoryItem(kind: .image, text: "图片 10×10",
                                        imageFile: "ABCD-1234.png")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardHistoryItem.self, from: data)
        XCTAssertEqual(decoded.imageFile, "ABCD-1234.png")
    }

    func test_itemCodable_legacyJSONWithoutNewFields() throws {
        // 旧版本 JSON：无 sourceAppName/sourceBundleID/imageFile 字段，必须可解
        let legacy = """
        {"id":"11111111-2222-3333-4444-555555555555","kind":"text","text":"hello",
         "imageData":null,"filePaths":null,
         "addedAt":725942400,"isFavorite":false}
        """
        let decoded = try JSONDecoder().decode(ClipboardHistoryItem.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.text, "hello")
        XCTAssertNil(decoded.sourceAppName)
        XCTAssertNil(decoded.sourceBundleID)
        XCTAssertNil(decoded.imageFile)
    }

    func test_itemCodable_sourceAppRoundTrip() throws {
        let item = ClipboardHistoryItem(kind: .text, text: "hello",
                                        sourceAppName: "Safari",
                                        sourceBundleID: "com.apple.Safari")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardHistoryItem.self, from: data)
        XCTAssertEqual(decoded.sourceAppName, "Safari")
        XCTAssertEqual(decoded.sourceBundleID, "com.apple.Safari")
    }

    // MARK: - 外置化（编码不内联 PNG）

    func test_itemEncode_externalizedImageSkipsInlinePNG() throws {
        // 已外置（imageFile 有值）的条目：编码不得再内联 imageData（JSON 膨胀根因）
        let item = ClipboardHistoryItem(kind: .image, text: "图片 10×10",
                                        imageData: Data([0x89, 0x50, 0x4E, 0x47]),
                                        imageFile: "ABC.png")
        let json = String(data: try JSONEncoder().encode(item), encoding: .utf8)!
        XCTAssertFalse(json.contains("aUpr"), "外置条目不得编码 imageData（base64 内联）")
        XCTAssertNil(try JSONDecoder().decode(ClipboardHistoryItem.self, from: Data(json.utf8)).imageData)
        XCTAssertEqual(try JSONDecoder().decode(ClipboardHistoryItem.self, from: Data(json.utf8)).imageFile, "ABC.png")
    }

    func test_store_attachImageFile_updatesItem() {
        var store = ClipboardHistoryStore(capacity: 5)
        let item = ClipboardHistoryItem(kind: .image, text: "图片 10×10", imageData: Data([1]))
        store.add(item)
        XCTAssertTrue(store.attachImageFile(id: item.id, fileName: "X.png"))
        XCTAssertEqual(store.items.first?.imageFile, "X.png")
        XCTAssertFalse(store.attachImageFile(id: UUID(), fileName: "Y.png"), "不存在的条目返回失败")
    }
}
