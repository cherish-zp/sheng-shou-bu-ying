import XCTest
import AppKit

/// TDD: 片段列表单元格完整排布——key 与预览文字不得被垂直裁切/压扁
/// （修复：44pt 行高下旧边距过约束，真实表格里预览行被压扁、每个字只见上半截）。
final class SnippetCellLayoutTests: XCTestCase {

    /// 列表行高（与 SnippetManagerView 的 tableView.rowHeight 一致）。
    private let rowHeight: CGFloat = 52

    @MainActor
    func test_labelsFullyVisibleAndUncompressed() {
        let cell = SnippetCellView(frame: NSRect(x: 0, y: 0, width: 200, height: rowHeight))
        cell.configure(key: "ftp", content: "sftp://example.com/home")
        cell.layoutSubtreeIfNeeded()

        let fields = cell.subviews.compactMap { $0 as? NSTextField }
        XCTAssertEqual(fields.count, 2, "key + 预览两行")
        for field in fields {
            let f = field.frame
            XCTAssertGreaterThanOrEqual(f.minY, -0.5, "顶部不得被裁: \(f)")
            XCTAssertLessThanOrEqual(f.maxY, cell.bounds.height + 0.5,
                                     "底部不得被裁: \(f)")
            // label 高度必须容纳其字号的整行文本（被压扁 = 字看一半）
            let pointSize = field.font?.pointSize ?? 0
            XCTAssertGreaterThanOrEqual(f.height, pointSize * 1.15,
                "label 被垂直压扁: 高 \(f.height) 装不下 \(pointSize)pt 整行")
        }
    }

    /// 约束未被打破的硬证据：key 顶距恰为约束常量 6。
    /// 旧实现 44pt 行高 + 8/8 边距（8+16+2+14+8=48 > 44）过约束，autolayout 打破
    /// 哪条因宿主环境而异——真实表格里打破的是预览行高度，字被裁一半。
    @MainActor
    func test_keyTopPaddingConstraintIsSatisfied() {
        let cell = SnippetCellView(frame: NSRect(x: 0, y: 0, width: 200, height: rowHeight))
        cell.configure(key: "ftp", content: "sftp://example.com/home")
        cell.layoutSubtreeIfNeeded()

        let keyLabel = cell.subviews.compactMap { $0 as? NSTextField }
            .first { $0.font?.pointSize == 13 }
        let previewLabel = cell.subviews.compactMap { $0 as? NSTextField }
            .first { $0.font?.pointSize == 11 }
        XCTAssertNotNil(keyLabel)
        XCTAssertNotNil(previewLabel)
        guard let keyLabel, let previewLabel else { return }

        let topGap = cell.bounds.height - keyLabel.frame.maxY
        XCTAssertEqual(topGap, 6, accuracy: 0.5, "key 顶距应为约束值 6，被打破说明行高不足")

        // 两行间距恰为约束值 2（key 在上、预览在下；底基坐标系）
        let gap = keyLabel.frame.minY - previewLabel.frame.maxY
        XCTAssertEqual(gap, 2, accuracy: 0.5)
        // 预览底留白 ≥ 4（底基坐标下 label.minY 即底留白）
        XCTAssertGreaterThanOrEqual(previewLabel.frame.minY, 3.5)
    }
}
