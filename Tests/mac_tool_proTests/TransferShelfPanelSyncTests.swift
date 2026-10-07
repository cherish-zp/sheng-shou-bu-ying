import XCTest
import AppKit

/// TDD: 中转站面板与暂存库的显示同步。
/// 修复的 bug(截图为证):重启后面板显示空态占位「拖文件到这里暂存」,
/// 再拖入库内的同一文件也毫无反应——
/// 1) showPanel() 从不把 store 里已有的条目渲染到新建面板;
/// 2) accept() 在拖入 URL 全部命中去重时直接 return,不重新渲染。
/// 结果文件早已入库,面板却永远空白。
///
/// 另含去单例后的注入交互测试:视图层不再硬编码 PanelController.shared,
/// 通过 onAccept/onRemove/validateForDrag 闭包回到注入的 controller,
/// 因此 init(store:storageURL:) 注入路径可覆盖完整视图交互。
@MainActor
final class TransferShelfPanelSyncTests: XCTestCase {

    private var workDir: URL!
    private var storageURL: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        storageURL = workDir.appendingPathComponent("transfer_shelf.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    /// 在临时目录造一个真实存在的文件(purge 巡检要求文件存在)。
    private func makeRealFile(_ name: String) throws -> URL {
        let url = workDir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    func test_showPanelRendersPersistedItems() throws {
        let url = try makeRealFile("already-staged.zip")
        var store = TransferShelfStore()
        store.add(url: url)
        let controller = TransferShelfPanelController(store: store, storageURL: storageURL)

        controller.showPanel()

        let shelfView = try XCTUnwrap(controller.shelfView)
        let itemViews = TransferShelfPanelSyncTests.findAll(in: shelfView, of: TransferShelfItemView.self)
        XCTAssertEqual(itemViews.count, 1, "showPanel 必须把库内已有条目渲染到面板,而不是空态占位")
        let placeholders = TransferShelfPanelSyncTests.findAll(in: shelfView, of: NSTextField.self)
            .filter { $0.stringValue == "拖文件到这里暂存" }
        XCTAssertTrue(placeholders.allSatisfy(\.isHidden), "库内有条目时不得显示空态占位")
    }

    func test_acceptDuplicateUrlStillRendersItems() throws {
        let url = try makeRealFile("duplicate.zip")
        var store = TransferShelfStore()
        store.add(url: url)
        let controller = TransferShelfPanelController(store: store, storageURL: storageURL)
        controller.showPanel()

        // 再拖入库内的同一文件:去重不新增条目,但面板必须同步显示已有条目。
        controller.accept(urls: [url])

        let shelfView = try XCTUnwrap(controller.shelfView)
        let itemViews = TransferShelfPanelSyncTests.findAll(in: shelfView, of: TransferShelfItemView.self)
        XCTAssertEqual(itemViews.count, 1, "去重后仍应渲染库内条目,给用户可见反馈")
    }

    func test_acceptNewUrlRendersItem() throws {
        let controller = TransferShelfPanelController(store: TransferShelfStore(), storageURL: storageURL)
        controller.showPanel()

        let url = try makeRealFile("fresh.txt")
        controller.accept(urls: [url])

        let shelfView = try XCTUnwrap(controller.shelfView)
        let itemViews = TransferShelfPanelSyncTests.findAll(in: shelfView, of: TransferShelfItemView.self)
        XCTAssertEqual(itemViews.count, 1, "拖入新文件应立即显示")
    }

    // MARK: - 注入式视图交互(去单例)

    func test_shelfViewOnAcceptInjectionAddsItemToStoreAndRenders() throws {
        let controller = TransferShelfPanelController(store: TransferShelfStore(), storageURL: storageURL)
        controller.showPanel()
        let url = try makeRealFile("injected-drop.txt")

        // 模拟 ShelfView 收到拖入:回调必须打到注入的 controller,而非全局单例。
        try XCTUnwrap(controller.shelfView).onAccept?([url])

        XCTAssertEqual(controller.store.items.map(\.url), [url], "视图回调应更新注入的 store")
        let shelfView = try XCTUnwrap(controller.shelfView)
        XCTAssertEqual(
            TransferShelfPanelSyncTests.findAll(in: shelfView, of: TransferShelfItemView.self).count, 1
        )
    }

    func test_shelfViewOnRemoveInjectionUpdatesStore() throws {
        let controller = TransferShelfPanelController(store: TransferShelfStore(), storageURL: storageURL)
        controller.showPanel()
        let url = try makeRealFile("to-remove.txt")
        try XCTUnwrap(controller.shelfView).onAccept?([url])
        let id = try XCTUnwrap(controller.store.items.first?.id)

        try XCTUnwrap(controller.shelfView).onRemove?(id)

        XCTAssertTrue(controller.store.items.isEmpty, "条目视图的移除回调应删掉注入 store 中的条目")
        let shelfView = try XCTUnwrap(controller.shelfView)
        XCTAssertEqual(
            TransferShelfPanelSyncTests.findAll(in: shelfView, of: TransferShelfItemView.self).count, 0,
            "移除后面板应回到空态"
        )
    }

    func test_validateForDragInjectionRemovesMissingFile() throws {
        let controller = TransferShelfPanelController(store: TransferShelfStore(), storageURL: storageURL)
        controller.showPanel()
        let url = try makeRealFile("will-vanish.txt")
        try XCTUnwrap(controller.shelfView).onAccept?([url])
        let id = try XCTUnwrap(controller.store.items.first?.id)
        try FileManager.default.removeItem(at: url)

        let allowed = try XCTUnwrap(controller.shelfView).validateForDrag?(id)

        XCTAssertEqual(allowed, false, "文件已不存在时拖出校验必须拒绝")
        XCTAssertTrue(controller.store.items.isEmpty, "校验拒绝的同时应从中转站移除失效条目")
    }

    func test_hotZoneDropAcceptsFiles() throws {
        let controller = TransferShelfPanelController(store: TransferShelfStore(), storageURL: storageURL)
        let url = try makeRealFile("hotzone-drop.txt")

        controller.dragSessionStarted()
        let hotZoneView = try XCTUnwrap(controller.hotZoneView, "拖拽会话开始必须激活热区视图")
        // 第二棒起热区回调统一为 onContentDropped（四类内容），文件走 intake 解析通道
        hotZoneView.onContentDropped?(
            TransferItemKindIntake.result(fileURLs: [url], pngData: nil, text: nil, urlStrings: [])
        )

        XCTAssertEqual(controller.store.items.map(\.url), [url], "热区落入的文件必须入列(不再被静默吞掉)")
    }

    // MARK: - 显隐状态机(集成)

    func test_showHideStateTransitions() {
        let controller = TransferShelfPanelController(store: TransferShelfStore(), storageURL: storageURL)

        controller.showPanel()
        XCTAssertEqual(controller.visibilityState, .showing)

        controller.hidePanel()
        XCTAssertEqual(controller.visibilityState, .hiding)
    }

    func test_repeatedHideWhileHidingDoesNotRestartAnimation() throws {
        let controller = TransferShelfPanelController(store: TransferShelfStore(), storageURL: storageURL)
        controller.showPanel()
        controller.hidePanel()

        // 第二次 hide 应被状态机拒绝(hidePanel 返回 false 表示未起新动画)
        XCTAssertFalse(controller.hidePanel(), "重复 hide 不应重新开始隐藏动画")
        XCTAssertEqual(controller.visibilityState, .hiding)
    }

    func test_showDuringHideInterrupts() throws {
        let controller = TransferShelfPanelController(store: TransferShelfStore(), storageURL: storageURL)
        controller.showPanel()
        controller.hidePanel()

        XCTAssertTrue(controller.showPanel(), "show 应能打断进行中的 hide")
        XCTAssertEqual(controller.visibilityState, .showing)
    }

    private static func findAll<T: NSView>(in root: NSView, of type: T.Type) -> [T] {
        var found: [T] = []
        for sub in root.subviews {
            if let hit = sub as? T { found.append(hit) }
            found.append(contentsOf: findAll(in: sub, of: type))
        }
        return found
    }
}
