import XCTest
import AppKit

/// TDD: 中转站卡片流布局——无滚动（不出现滚动条），卡片完整可见，
/// 超宽自动换行到下一行（面板随行数拉长）。
final class TransferShelfDropLayoutTests: XCTestCase {

    @MainActor
    func test_noScrollViewInHierarchy() {
        let shelf = TransferShelfShelfView(frame: NSRect(origin: .zero,
                size: TransferShelfLayoutSpec.panelSize(itemCount: 2, screenWidth: 1512)))
        shelf.render(items: [])
        shelf.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            TransferShelfDropLayoutTests.findAll(in: shelf, of: NSScrollView.self).isEmpty,
            "卡片流布局不允许滚动条：面板尺寸必须随内容拉长"
        )
    }

    @MainActor
    func test_renderedCardLiesFullyInsidePanel() {
        let size = TransferShelfLayoutSpec.panelSize(itemCount: 1, screenWidth: 1512)
        let shelf = TransferShelfShelfView(frame: NSRect(origin: .zero, size: size))
        shelf.render(items: [TransferItem(url: URL(fileURLWithPath: "/tmp/shelf-card-test.txt"))])
        shelf.layoutSubtreeIfNeeded()

        let cards = TransferShelfDropLayoutTests.findAll(in: shelf, of: TransferShelfItemView.self)
        XCTAssertEqual(cards.count, 1, "拖入后应渲染出一张卡片")

        guard let card = cards.first else { return }
        let cardRect = shelf.convert(card.bounds, from: card)
        XCTAssertTrue(
            shelf.bounds.contains(cardRect.insetBy(dx: -0.5, dy: -0.5)),
            "卡片必须完整落在面板内: card=\(cardRect) bounds=\(shelf.bounds)"
        )
    }

    @MainActor
    func test_overflowItemsWrapToSecondRow() {
        // 窄屏强换行：500 宽屏 6 张卡 → 一行 4 张 → 2 行，全部可见且无滚动
        let screenWidth: CGFloat = 500
        let size = TransferShelfLayoutSpec.panelSize(itemCount: 6, screenWidth: screenWidth)
        let shelf = TransferShelfShelfView(frame: NSRect(origin: .zero, size: size))
        shelf.currentScreenWidth = screenWidth
        let items = (0..<6).map { TransferItem(url: URL(fileURLWithPath: "/tmp/wrap-\($0).txt")) }
        shelf.render(items: items)
        shelf.layoutSubtreeIfNeeded()

        let cards = TransferShelfDropLayoutTests.findAll(in: shelf, of: TransferShelfItemView.self)
        XCTAssertEqual(cards.count, 6)

        let yOrigins = Set(cards.map { shelf.convert($0.bounds.origin, from: $0).y.rounded() })
        XCTAssertGreaterThanOrEqual(yOrigins.count, 2, "超出一行应换行到第二行")

        for card in cards {
            let rect = shelf.convert(card.bounds, from: card)
            XCTAssertTrue(shelf.bounds.contains(rect.insetBy(dx: -0.5, dy: -0.5)),
                          "换行后每张卡片仍须完整可见: rect=\(rect)")
        }
        XCTAssertTrue(TransferShelfDropLayoutTests.findAll(in: shelf, of: NSScrollView.self).isEmpty)
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
