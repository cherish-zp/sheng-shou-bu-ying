import XCTest
import AppKit

/// TDD: 文件中转站拖入后的条目渲染布局。
/// 修复的 bug:拖入文件后面板不显示条目——stackView 作为 scrollView 的
/// documentView,translatesAutoresizingMaskIntoConstraints = false 却没有
/// 任何约束钉到 contentLayoutGuide,documentView 布局无定义,条目
/// 渲染在零尺寸/越界区域里,肉眼不可见。
final class TransferShelfDropLayoutTests: XCTestCase {

    @MainActor
    func test_renderedItemLiesInsideVisibleScrollArea() {
        // 面板高度用「1 个条目 + 头部栏」的规格值：头部栏引入后旧 68pt 放不下 44pt 条目
        let shelf = TransferShelfShelfView(frame: NSRect(x: 0, y: 0, width: 210, height: TransferShelfLayoutSpec.panelHeight(itemCount: 1)))
        let item = TransferItem(url: URL(fileURLWithPath: "/tmp/transfer-shelf-drop-test.txt"))
        shelf.render(items: [item])
        shelf.layoutSubtreeIfNeeded()

        let itemViews = TransferShelfDropLayoutTests.findAll(in: shelf, of: TransferShelfItemView.self)
        XCTAssertEqual(itemViews.count, 1, "拖入后应渲染出一个条目视图")

        guard let itemView = itemViews.first else { return }
        let visibleRect = shelf.convert(itemView.bounds, from: itemView)
        XCTAssertGreaterThan(visibleRect.width, 0, "条目宽度必须大于 0")
        XCTAssertGreaterThan(visibleRect.height, 0, "条目高度必须大于 0")
        XCTAssertTrue(
            shelf.bounds.intersection(visibleRect).height >= visibleRect.height * 0.99,
            "条目必须完整落在面板可视区域内: itemRect=\(visibleRect) bounds=\(shelf.bounds)"
        )
    }

    @MainActor
    func test_documentViewIsPinnedToScrollContentLayout() {
        let shelf = TransferShelfShelfView(frame: NSRect(x: 0, y: 0, width: 210, height: TransferShelfLayoutSpec.panelHeight))
        shelf.layoutSubtreeIfNeeded()

        guard let scrollView = TransferShelfDropLayoutTests.findAll(in: shelf, of: NSScrollView.self).first,
              let stack = scrollView.documentView as? NSStackView else {
            return XCTFail("面板应包含以 NSStackView 为 documentView 的滚动区")
        }
        XCTAssertGreaterThan(stack.frame.width, 0, "documentView 宽度必须大于 0(约束钉住 contentLayoutGuide)")
        XCTAssertGreaterThanOrEqual(stack.frame.width, scrollView.contentSize.width - 0.5,
                                    "documentView 宽度应与可视内容区一致,否则条目横向不可见")
        XCTAssertGreaterThanOrEqual(stack.frame.height, 0.5)
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
