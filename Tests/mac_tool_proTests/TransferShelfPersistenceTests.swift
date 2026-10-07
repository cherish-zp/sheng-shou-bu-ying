import XCTest
import Foundation

/// TDD: 中转站持久化健壮性。
/// 1) loadPersisted 不得触发冗余回写（此前 store.didSet 无条件 persist）；
/// 2) 损坏文件不再无声清空——改名备份 .corrupt-* 并落 DiagLog；
/// 3) 注入的 store 变化要真实落到磁盘（.atomic）。
@MainActor
final class TransferShelfPersistenceTests: XCTestCase {

    private var workDir: URL!
    private var storageURL: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-persist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        storageURL = workDir.appendingPathComponent("transfer_shelf.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    /// 预写持久化文件并把 mtime 拨回过去（.atomic 写会产生新 mtime，据此判定回写）。
    private func prewriteStorage(_ data: Data) throws {
        try data.write(to: storageURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -1_000)],
            ofItemAtPath: storageURL.path
        )
    }

    private func persistedItems() throws -> [TransferItem] {
        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TransferItem].self, from: data)
    }

    private func modificationDate(at url: URL) throws -> Date {
        try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        )
    }

    func test_loadPersistedDoesNotRewriteFile() throws {
        var store = TransferShelfStore()
        store.add(url: URL(fileURLWithPath: "/tmp/persisted.txt"))
        try prewriteStorage(XCTUnwrap(store.encode()))

        _ = TransferShelfPanelController(storageURL: storageURL)

        let mtime = try modificationDate(at: storageURL)
        XCTAssertLessThan(
            mtime.timeIntervalSinceNow, -500,
            "loadPersisted 只应恢复数据，不得触发冗余回写"
        )
    }

    func test_corruptFileIsQuarantinedAndShelfStartsEmpty() throws {
        try Data("not-json-at-all{{".utf8).write(to: storageURL)

        let controller = TransferShelfPanelController(storageURL: storageURL)

        XCTAssertTrue(controller.store.items.isEmpty, "损坏数据应以空库继续")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: workDir.path)
        XCTAssertTrue(
            leftovers.contains { $0.hasPrefix("transfer_shelf.json.corrupt-") },
            "损坏文件必须改名备份（.corrupt-yyyyMMddHHmmss），实际目录: \(leftovers)"
        )
    }

    func test_acceptPersistsItemsToDisk() throws {
        let controller = TransferShelfPanelController(
            store: TransferShelfStore(),
            storageURL: storageURL
        )
        controller.showPanel()
        let url = workDir.appendingPathComponent("staged.txt")
        try Data("x".utf8).write(to: url)

        controller.shelfView?.onAccept?([url])

        let items = try persistedItems()
        XCTAssertEqual(items.map(\.url), [url], "注入路径拖入的条目必须落盘（.atomic 写入）")
    }

    func test_maxCountSurvivesPersistenceRoundtrip() throws {
        let controller = TransferShelfPanelController(
            store: TransferShelfStore(maxCount: 7),
            storageURL: storageURL
        )
        controller.showPanel()
        let url = workDir.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: url)
        controller.shelfView?.onAccept?([url])

        // 用相同 maxCount 重新加载：上限配置不得丢失
        let reloaded = TransferShelfPanelController(storageURL: storageURL, maxCount: 7)
        XCTAssertEqual(reloaded.store.maxCount, 7)
        XCTAssertEqual(reloaded.store.items.map(\.url), [url])
    }
}
