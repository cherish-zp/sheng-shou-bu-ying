import XCTest
import AppKit

/// TDD: 中转站卡片流布局——单行横向卡片流（对标剪贴板面板语言）：
/// 高度恒定不换行；溢出横向滚动（滚轮纵转横共享视图）；卡片完整落在文档内。
final class TransferShelfDropLayoutTests: XCTestCase {

    @MainActor
    func test_cardFlowUsesSharedHorizontalScrollView() {
        let shelf = TransferShelfShelfView(frame: NSRect(origin: .zero,
                size: TransferShelfLayoutSpec.panelSize(itemCount: 2, screenWidth: 1512)))
        shelf.render(items: [])
        shelf.layoutSubtreeIfNeeded()
        // 卡片流必须使用共享 HorizontalScrollScrollView（滚轮纵转横，与剪贴板面板同源）
        let scrolls = TransferShelfDropLayoutTests.findAll(in: shelf, of: HorizontalScrollScrollView.self)
        XCTAssertEqual(scrolls.count, 1, "应有且只有一个共享横向滚动视图")
    }

    @MainActor
    func test_renderedCardLiesFullyInsideDocument() {
        let size = TransferShelfLayoutSpec.panelSize(itemCount: 1, screenWidth: 1512)
        let shelf = TransferShelfShelfView(frame: NSRect(origin: .zero, size: size))
        shelf.render(items: [TransferItem(url: URL(fileURLWithPath: "/tmp/shelf-card-test.txt"))])
        shelf.layoutSubtreeIfNeeded()

        let cards = TransferShelfDropLayoutTests.findAll(in: shelf, of: TransferShelfItemView.self)
        XCTAssertEqual(cards.count, 1, "拖入后应渲染出一张卡片")

        guard let card = cards.first, let scroll = TransferShelfDropLayoutTests.findAll(in: shelf, of: HorizontalScrollScrollView.self).first,
              let doc = scroll.documentView else { return }
        let cardRect = doc.convert(card.bounds, from: card)
        XCTAssertTrue(
            doc.bounds.contains(cardRect.insetBy(dx: 0.5, dy: 0.5)),
            "卡片必须完整落在文档内: card=\(cardRect) bounds=\(doc.bounds)"
        )
    }

    @MainActor
    func test_overflowCardsScrollHorizontally_noWrapNoVerticalGrowth() {
        // 20 条（maxCount 上限）：单行横向摆放——y 全部相同（不换行），
        // 内容总宽超出面板可视宽（滚动承载），面板高度恒定。
        let screenWidth: CGFloat = 800
        let size = TransferShelfLayoutSpec.panelSize(itemCount: 20, screenWidth: screenWidth)
        let shelf = TransferShelfShelfView(frame: NSRect(origin: .zero, size: size))
        shelf.currentScreenWidth = screenWidth
        let items = (0..<20).map { TransferItem(url: URL(fileURLWithPath: "/tmp/ovf-\($0).txt")) }
        shelf.render(items: items)
        shelf.layoutSubtreeIfNeeded()

        let cards = TransferShelfDropLayoutTests.findAll(in: shelf, of: TransferShelfItemView.self)
        XCTAssertEqual(cards.count, 20)

        // 单行：全部卡片同一 y
        let yOrigins = Set(cards.map { shelf.convert($0.bounds.origin, from: $0).y.rounded() })
        XCTAssertEqual(yOrigins.count, 1, "单行横向流不得换行（y 应唯一）")

        // 溢出滚动：内容总宽 > 面板宽
        guard let scroll = TransferShelfDropLayoutTests.findAll(in: shelf, of: HorizontalScrollScrollView.self).first,
              let doc = scroll.documentView else { return XCTFail("应有共享横向滚动视图") }
        XCTAssertGreaterThan(doc.frame.width, scroll.contentView.bounds.width,
                             "20 条在 800 宽屏必须溢出（横向滚动承载）")
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
