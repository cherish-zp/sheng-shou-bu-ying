import XCTest

/// TDD: 重做栈 + 新标注类型（气泡/椭圆/直线，对标浮引工具条 1:1）。
/// 规则：undo 把标注压入重做栈；redo 弹出重新追加；新增标注清空重做栈；
/// 序号标注的撤销/重做都会回退/推进序号。
final class AnnotationRedoStackTests: XCTestCase {

    func test_newAnnotationTypes_exist() {
        XCTAssertTrue(AnnotationType.allCases.contains(.bubble))
        XCTAssertTrue(AnnotationType.allCases.contains(.oval))
        XCTAssertTrue(AnnotationType.allCases.contains(.line))
    }

    func test_undo_pushesToRedoStack() {
        let model = AnnotationModel()
        model.add(Annotation(type: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 9, y: 9)]))
        XCTAssertFalse(model.canRedo)
        model.undo()
        XCTAssertEqual(model.count, 0)
        XCTAssertTrue(model.canRedo)
    }

    func test_redo_reappendsPoppedAnnotation() {
        let model = AnnotationModel()
        model.add(Annotation(type: .arrow, points: [.zero, CGPoint(x: 5, y: 5)]))
        let undone = model.undo()
        XCTAssertEqual(model.count, 0)
        let redone = model.redo()
        XCTAssertEqual(redone?.id, undone?.id, "重做应恢复被撤销的同一标注")
        XCTAssertEqual(model.count, 1)
        XCTAssertFalse(model.canRedo, "重做后重做栈清空")
    }

    func test_add_invalidatesRedoStack() {
        let model = AnnotationModel()
        model.add(Annotation(type: .rectangle, points: [.zero, CGPoint(x: 1, y: 1)]))
        model.undo()
        model.add(Annotation(type: .mosaic, points: [.zero, CGPoint(x: 2, y: 2)]))
        XCTAssertFalse(model.canRedo, "新标注后不得再重做旧内容")
    }

    func test_counter_undoRedo_advancesAndRetractsCounter() {
        let model = AnnotationModel()
        model.addCounter(at: .zero, color: .red)
        model.undo()
        XCTAssertEqual(model.counterNext, 1, "撤销后序号回退")
        model.redo()
        XCTAssertEqual(model.counterNext, 2, "重做后序号推进")
    }

    func test_clear_emptiesBothStacks() {
        let model = AnnotationModel()
        model.add(Annotation(type: .pen, points: [.zero, CGPoint(x: 1, y: 1)]))
        model.undo()
        model.clear()
        XCTAssertFalse(model.canRedo)
    }

    func test_bubbleAnnotation_payload() {
        let annotation = Annotation(type: .bubble, points: [CGPoint(x: 3, y: 4)],
                                    text: "气泡内容", color: .red)
        XCTAssertEqual(annotation.type, AnnotationType.bubble)
        XCTAssertEqual(annotation.text, "气泡内容")
    }
}
