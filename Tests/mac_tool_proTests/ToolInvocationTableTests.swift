import XCTest

/// TDD: 调用表代次校验 —— Finder 可能对同一次交互多次调用 menu(for:)，或在上一次菜单
/// 未点击前再次构建：旧菜单项的 tag 按下标会静默命中"另一次构建"的调用（工具/路径错位）。
/// tag 编码代次（generation * stride + index），clear 递增代次，陈旧 tag 解析为 nil。
final class ToolInvocationTableTests: XCTestCase {

    func test_append_firstGeneration_tagIsIndex() {
        let table = ToolInvocationTable()
        let t0 = table.append(ToolInvocation(toolId: "a", urls: []))
        let t1 = table.append(ToolInvocation(toolId: "b", urls: []))
        XCTAssertEqual(t0, 0)
        XCTAssertEqual(t1, 1)
        XCTAssertEqual(table.resolve(tag: t0)?.toolId, "a")
        XCTAssertEqual(table.resolve(tag: t1)?.toolId, "b")
    }

    func test_clear_incrementsGeneration_staleTagResolvesNil() {
        let table = ToolInvocationTable()
        let staleTag = table.append(ToolInvocation(toolId: "a", urls: [URL(fileURLWithPath: "/old")]))
        table.clear()
        let newTag = table.append(ToolInvocation(toolId: "b", urls: [URL(fileURLWithPath: "/new")]))
        XCTAssertNil(table.resolve(tag: staleTag), "上一代菜单的 tag 不得命中新一次构建")
        XCTAssertEqual(table.resolve(tag: newTag)?.toolId, "b")
        XCTAssertEqual(table.resolve(tag: newTag)?.urls, [URL(fileURLWithPath: "/new")])
    }

    func test_clearRepeatedly_staleTagsStayNil() {
        let table = ToolInvocationTable()
        var staleTags: [Int] = []
        for round in 0..<5 {
            staleTags.append(table.append(ToolInvocation(toolId: "t\(round)", urls: [])))
            table.clear()
        }
        for (round, tag) in staleTags.enumerated() {
            XCTAssertNil(table.resolve(tag: tag), "第 \(round) 代 tag 应失效")
        }
        let liveTag = table.append(ToolInvocation(toolId: "live", urls: []))
        XCTAssertEqual(table.resolve(tag: liveTag)?.toolId, "live")
    }

    func test_resolve_outOfRangeOrNegative_isNil() {
        let table = ToolInvocationTable()
        table.append(ToolInvocation(toolId: "a", urls: []))
        XCTAssertNil(table.resolve(tag: -1))
        XCTAssertNil(table.resolve(tag: 999_999))
    }
}
