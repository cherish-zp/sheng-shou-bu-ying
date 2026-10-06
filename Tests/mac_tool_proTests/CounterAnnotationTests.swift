import XCTest
import CoreGraphics

/// TDD: 序号步骤标注 - 放置自动递增、重新选中复位、撤销回退、Codable 保留进度。
final class CounterAnnotationTests: XCTestCase {

    func test_addCounter_sequentialNumbers() {
        let model = AnnotationModel()
        let a1 = model.addCounter(at: CGPoint(x: 10, y: 10), color: .blue)
        let a2 = model.addCounter(at: CGPoint(x: 20, y: 20), color: .blue)
        let a3 = model.addCounter(at: CGPoint(x: 30, y: 30), color: .blue)
        XCTAssertEqual(a1.text, "1")
        XCTAssertEqual(a2.text, "2")
        XCTAssertEqual(a3.text, "3")
        XCTAssertEqual(a1.type, .counter)
        XCTAssertEqual(a1.points, [CGPoint(x: 10, y: 10)])
        XCTAssertEqual(a1.color, .blue)
    }

    func test_resetCounter_restartsFromOne() {
        let model = AnnotationModel()
        model.addCounter(at: .zero, color: .red)
        model.addCounter(at: .zero, color: .red)
        model.resetCounter()
        XCTAssertEqual(model.addCounter(at: .zero, color: .red).text, "1")
    }

    func test_undoCounter_stepsNumberBack() {
        let model = AnnotationModel()
        model.addCounter(at: .zero, color: .red)   // 1
        model.addCounter(at: .zero, color: .red)   // 2
        model.undo()  // 撤销 2 → 序号回退
        XCTAssertEqual(model.addCounter(at: .zero, color: .red).text, "2")
    }

    func test_undoNonCounter_keepsNumberProgress() {
        let model = AnnotationModel()
        model.addCounter(at: .zero, color: .red)   // 1
        model.add(Annotation(type: .rectangle, points: [.zero, CGPoint(x: 5, y: 5)]))
        model.undo()  // 撤销矩形
        XCTAssertEqual(model.addCounter(at: .zero, color: .red).text, "2")
    }

    func test_codable_preservesCounterProgress() throws {
        let model = AnnotationModel()
        model.addCounter(at: .zero, color: .red)
        model.addCounter(at: .zero, color: .red)
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(AnnotationModel.self, from: data)
        XCTAssertEqual(decoded.addCounter(at: .zero, color: .red).text, "3")
    }

    func test_codable_legacyDataDefaultsToOne() throws {
        // 旧版本数据无 counterNext 字段，解码后序号从 1 开始
        let legacyJSON = Data("{\"annotations\":[]}".utf8)
        let legacy = try JSONDecoder().decode(AnnotationModel.self, from: legacyJSON)
        XCTAssertEqual(legacy.addCounter(at: .zero, color: .red).text, "1")
    }

    func test_counterBadge_rectCenteredAtClickPoint() {
        let rect = CounterBadge.rect(centeredAt: CGPoint(x: 50, y: 60))
        XCTAssertEqual(rect.midX, 50)
        XCTAssertEqual(rect.midY, 60)
        XCTAssertEqual(rect.width, CounterBadge.diameter)
        XCTAssertEqual(rect.height, CounterBadge.diameter)
    }

    func test_counterBadge_fontSizeShrinksForMoreDigits() {
        XCTAssertEqual(CounterBadge.fontSize(forDigits: 1), CounterBadge.fontSize(forDigits: 2))
        XCTAssertLessThan(CounterBadge.fontSize(forDigits: 3), CounterBadge.fontSize(forDigits: 1))
        XCTAssertLessThan(CounterBadge.fontSize(forDigits: 5), CounterBadge.fontSize(forDigits: 3))
    }
}
