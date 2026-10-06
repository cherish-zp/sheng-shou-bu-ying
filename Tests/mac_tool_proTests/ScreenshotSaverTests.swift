import XCTest

/// ScreenshotSaver：统一保存出口，任何失败都必须落在 outcome.error，绝不静默。
final class ScreenshotSaverTests: XCTestCase {
    private var dir: URL!
    private var config: ScreenshotConfig!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("saver-tests-\(UUID().uuidString)")
        config = ScreenshotConfig(saveDirectory: dir, format: .png, filenamePrefix: "截屏")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        try super.tearDownWithError()
    }

    private func makeImage(width: Int = 8, height: Int = 8) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    func test成功保存返回URL并写入PNG数据() throws {
        let store = SpyFileStore()
        let saver = ScreenshotSaver(config: config, fileStore: store)

        let outcome = saver.save(makeImage())

        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.url?.deletingLastPathComponent().path, dir.path)
        XCTAssertEqual(outcome.url?.lastPathComponent.hasPrefix("截屏 "), true)
        XCTAssertEqual(outcome.url?.pathExtension, "png")
        XCTAssertEqual(store.createdDirectories.map(\.path), [dir.path])
        let data = try XCTUnwrap(store.written[outcome.url!.path])
        XCTAssertEqual(data.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "写入的是 PNG 数据")
    }

    /// 用日历组件构造固定日期，避免跨时区硬编码时间戳。
    private func makeFixedDate() -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!
    }

    func test同名文件自动去重() throws {
        let store = SpyFileStore()
        store.existingContents = ["截屏 2026-10-05 10.00.00.png"]
        let fixedDate = makeFixedDate()
        let saver = ScreenshotSaver(config: config, fileStore: store, now: { fixedDate })

        let outcome = saver.save(makeImage())

        XCTAssertEqual(outcome.url?.lastPathComponent, "截屏 2026-10-05 10.00.00 2.png")
    }

    func test建目录失败返回directoryCreationFailed() {
        let store = SpyFileStore()
        store.createDirectoryError = NSError(domain: "test", code: 1)
        let saver = ScreenshotSaver(config: config, fileStore: store)

        let outcome = saver.save(makeImage())

        XCTAssertEqual(outcome.error, .directoryCreationFailed)
        XCTAssertNil(outcome.url)
    }

    func test列目录失败返回listingFailed() {
        let store = SpyFileStore()
        store.listingError = NSError(domain: "test", code: 2)
        let saver = ScreenshotSaver(config: config, fileStore: store)

        let outcome = saver.save(makeImage())

        XCTAssertEqual(outcome.error, .listingFailed)
        XCTAssertNil(outcome.url)
    }

    func test编码失败返回encodingFailed() {
        let store = SpyFileStore()
        let saver = ScreenshotSaver(config: config, fileStore: store, encoder: { _ in nil })

        let outcome = saver.save(makeImage())

        XCTAssertEqual(outcome.error, .encodingFailed)
        XCTAssertNil(outcome.url)
        XCTAssertTrue(store.written.isEmpty, "编码失败不得写盘")
    }

    func test写盘失败返回writeFailed() {
        let store = SpyFileStore()
        store.writeError = NSError(domain: "test", code: 3)
        let saver = ScreenshotSaver(config: config, fileStore: store)

        let outcome = saver.save(makeImage())

        guard case .writeFailed? = outcome.error else {
            return XCTFail("期望 writeFailed，实际 \(String(describing: outcome.error))")
        }
        XCTAssertNil(outcome.url)
    }

    func test默认存储走真实文件系统() throws {
        let saver = ScreenshotSaver(config: config)

        let outcome = saver.save(makeImage())

        XCTAssertNil(outcome.error)
        let data = try Data(contentsOf: XCTUnwrap(outcome.url))
        XCTAssertEqual(data.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "落盘为 PNG 魔数")
    }
}

/// 注入用文件存储 spy：记录调用并可按需抛错。
final class SpyFileStore: ScreenshotFileStore {
    var createdDirectories: [URL] = []
    var written: [String: Data] = [:]
    var existingContents: [String] = []
    var createDirectoryError: Error?
    var listingError: Error?
    var writeError: Error?

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        if let error = createDirectoryError { throw error }
        createdDirectories.append(url)
    }

    func contentsOfDirectory(at url: URL) throws -> [String] {
        if let error = listingError { throw error }
        return existingContents
    }

    func write(_ data: Data, to url: URL) throws {
        if let error = writeError { throw error }
        written[url.path] = data
    }
}
