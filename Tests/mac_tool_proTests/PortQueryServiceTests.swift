import XCTest

/// TDD: lsof 输出解码容错 —— 全部连接模式下输出可能含非 UTF-8 字节
/// （进程名/套接字标识携带原始字节），解码必须无损容错而非整块丢弃。
final class PortQueryServiceTests: XCTestCase {

    func test_query_decodesNonUTF8Output_lossily() {
        let service = PortQueryService()
        // 非法 UTF-8 序列（0xFF）+ 有效行：整块 String(data:encoding:) 会返回 nil → 旧实现 0 条
        var payload = Data([0xFF, 0xFE])
        payload.append(Data("\nnode 123 zhangpeng 1u IPv4 0x0 0t0 TCP *:3000 (LISTEN)\n".utf8))
        service.runner = { _ in (payload, 0) }

        let expectation = expectation(description: "query completion")
        var entries: [PortProcessEntry]?
        service.query(mode: .all) {
            if case .success(let list) = $0 { entries = list }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(entries?.count, 1, "非法字节不应吞掉整份输出")
        XCTAssertEqual(entries?.first?.port, 3000)
    }

    func test_query_lsofUnavailable_reportsError() {
        let service = PortQueryService()
        service.runner = { _ in nil }
        let expectation = expectation(description: "query completion")
        var error: Error?
        service.query(mode: .listening) {
            if case .failure(let e) = $0 { error = e }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        XCTAssertNotNil(error)
    }
}
