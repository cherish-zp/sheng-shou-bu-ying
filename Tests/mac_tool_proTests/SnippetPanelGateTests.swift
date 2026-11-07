import XCTest

/// TDD: 快速片段面板编辑态交互裁决。
/// 背景：编辑浮层旧实现为 nonactivatingPanel——永远无法成为 key，鼠标/键盘
/// 事件路由不可靠（真机实证：点「取消」无响应、Esc 失效）。修复为普通 key
/// 窗口后需要两道状态裁决：Esc 分流、主面板失焦抑制。
final class SnippetPanelGateTests: XCTestCase {

    func test_esc_withEditorOpen_closesEditorOnly() {
        XCTAssertEqual(SnippetPanelGate.escAction(hasEditor: true), .closeEditor,
                       "编辑浮层开着时 Esc 只取消编辑，不关主面板")
    }

    func test_esc_withoutEditor_hidesPanel() {
        XCTAssertEqual(SnippetPanelGate.escAction(hasEditor: false), .hidePanel)
    }

    func test_resign_withEditorOpen_doesNotHidePanel() {
        XCTAssertFalse(SnippetPanelGate.resignShouldHidePanel(hasEditor: true),
                       "编辑浮层抢走 key 时主面板失焦是预期行为，不得自动关闭")
    }

    func test_resign_withoutEditor_hidesPanel() {
        XCTAssertTrue(SnippetPanelGate.resignShouldHidePanel(hasEditor: false))
    }
}
