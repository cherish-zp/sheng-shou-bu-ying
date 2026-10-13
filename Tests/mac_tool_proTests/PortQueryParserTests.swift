import XCTest

/// TDD: lsof 输出解析 —— 表头跳过、IPv4/IPv6 去重、UDP 无状态、地址取端口、
/// 异常行跳过、当前用户归属。
final class PortQueryParserTests: XCTestCase {

    private let header = "COMMAND   PID USER   FD   TYPE  DEVICE SIZE/OFF NODE NAME"

    func test_parseListenOutput_dedupsDualStack() {
        let output = """
        \(header)
        node     1234 zhangpeng   23u  IPv4  0xt1      0t0  TCP *:3000 (LISTEN)
        node     1234 zhangpeng   24u  IPv6  0xt2      0t0  TCP [::]:3000 (LISTEN)
        """
        let entries = PortQueryParser.parse(output, currentUserName: "zhangpeng")
        XCTAssertEqual(entries.count, 1, "IPv4+IPv6 双栈监听同一端口应去重为一行")
        let entry = try! XCTUnwrap(entries.first)
        XCTAssertEqual(entry.port, 3000)
        XCTAssertEqual(entry.protocolName, "TCP")
        XCTAssertEqual(entry.pid, 1234)
        XCTAssertEqual(entry.processName, "node")
        XCTAssertEqual(entry.user, "zhangpeng")
        XCTAssertEqual(entry.state, "LISTEN")
        XCTAssertEqual(entry.address, "*:3000")
        XCTAssertTrue(entry.isCurrentUser)
    }

    func test_parseUDP_hasNoState() {
        let output = """
        \(header)
        chrome   999 zhangpeng   40u  IPv4  0xu1      0t0  UDP *:5353
        """
        let entries = PortQueryParser.parse(output, currentUserName: "zhangpeng")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].protocolName, "UDP")
        XCTAssertEqual(entries[0].state, "", "UDP 无连接状态")
        XCTAssertEqual(entries[0].port, 5353)
    }

    func test_parseLoopbackAndEstablished() {
        let output = """
        \(header)
        myapp    777 zhangpeng   12u  IPv4  0xe1      0t0  TCP 127.0.0.1:8080->127.0.0.1:52000 (ESTABLISHED)
        """
        let entries = PortQueryParser.parse(output, currentUserName: "zhangpeng")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].state, "ESTABLISHED")
        XCTAssertEqual(entries[0].address, "127.0.0.1:8080->127.0.0.1:52000")
        XCTAssertEqual(entries[0].port, 8080, "取本地端地址的端口")
    }

    func test_parseOtherUser_isNotCurrentUser() {
        let output = """
        \(header)
        mysqld   5678 _mysql   15u  IPv6  0xm1      0t0  TCP *:3306 (LISTEN)
        sshd     111 root     3u  IPv4  0xs1      0t0  TCP *:22 (LISTEN)
        """
        let entries = PortQueryParser.parse(output, currentUserName: "zhangpeng")
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { !$0.isCurrentUser })
    }

    func test_parseSkipsHeaderAndMalformedLines() {
        let output = """
        \(header)
        这行不是有效输出
        node not-a-pid zhangpeng 1u IPv4 0x 0t0 TCP *:3000 (LISTEN)
        lsof: WARNING: something odd
        \(header)
        """
        XCTAssertTrue(PortQueryParser.parse(output, currentUserName: "u").isEmpty)
    }

    func test_parseEmptyOutput() {
        XCTAssertTrue(PortQueryParser.parse("", currentUserName: "u").isEmpty)
        XCTAssertTrue(PortQueryParser.parse(header, currentUserName: "u").isEmpty)
    }

    func test_portNumber_fromAddressForms() {
        XCTAssertEqual(PortQueryParser.portNumber(from: "*:3000"), 3000)
        XCTAssertEqual(PortQueryParser.portNumber(from: "[::]:8080"), 8080)
        XCTAssertEqual(PortQueryParser.portNumber(from: "127.0.0.1:6379"), 6379)
        XCTAssertNil(PortQueryParser.portNumber(from: "no-port-here"))
    }
}
