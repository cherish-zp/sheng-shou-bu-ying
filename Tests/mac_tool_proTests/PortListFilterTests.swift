import XCTest

/// TDD: 端口列表过滤 —— 仅监听语义（TCP LISTEN + 全部 UDP）与搜索（进程名/端口/PID）。
final class PortListFilterTests: XCTestCase {

    private func entry(port: Int, proto: String = "TCP", pid: Int = 1,
                       name: String = "app", state: String = "LISTEN") -> PortProcessEntry {
        PortProcessEntry(port: port, protocolName: proto, pid: pid, processName: name,
                         user: "u", address: "*:\(port)", state: state, isCurrentUser: true)
    }

    func test_listenOnly_keepsTCPListenAndAllUDP_dropsEstablished() {
        let entries = [
            entry(port: 3000, state: "LISTEN"),
            entry(port: 4000, proto: "UDP", state: ""),
            entry(port: 5000, state: "ESTABLISHED"),
            entry(port: 6000, state: "TIME_WAIT"),
        ]
        let filtered = PortListFilter(listenOnly: true).apply(entries)
        XCTAssertEqual(filtered.map(\.port), [3000, 4000], "TCP 只留 LISTEN，UDP 绑定即监听全保留")
    }

    func test_listenOnlyOff_keepsEverything() {
        let entries = [entry(port: 3000), entry(port: 5000, state: "ESTABLISHED")]
        XCTAssertEqual(PortListFilter(listenOnly: false).apply(entries).count, 2)
    }

    func test_searchMatchesProcessNameCaseInsensitive() {
        let entries = [entry(port: 3000, name: "Node"), entry(port: 4000, name: "mysqld")]
        let filtered = PortListFilter(listenOnly: false, searchText: "node").apply(entries)
        XCTAssertEqual(filtered.map(\.port), [3000])
    }

    func test_searchMatchesPortNumber() {
        let entries = [entry(port: 3000), entry(port: 4000)]
        let filtered = PortListFilter(listenOnly: false, searchText: "400").apply(entries)
        XCTAssertEqual(filtered.map(\.port), [4000])
    }

    func test_searchMatchesPid() {
        let entries = [entry(port: 3000, pid: 1234), entry(port: 4000, pid: 5678)]
        let filtered = PortListFilter(listenOnly: false, searchText: "1234").apply(entries)
        XCTAssertEqual(filtered.map(\.pid), [1234])
    }

    func test_searchWhitespaceOnly_matchesAll() {
        let entries = [entry(port: 3000), entry(port: 4000)]
        XCTAssertEqual(PortListFilter(listenOnly: false, searchText: "   ").apply(entries).count, 2)
    }

    func test_combinedListenAndSearch() {
        let entries = [
            entry(port: 3000, name: "node", state: "LISTEN"),
            entry(port: 5000, name: "node", state: "ESTABLISHED"),
        ]
        let filtered = PortListFilter(listenOnly: true, searchText: "node").apply(entries)
        XCTAssertEqual(filtered.map(\.port), [3000])
    }
}

/// kill 终止序列的信号计划。
final class PortKillStrategyTests: XCTestCase {

    func test_signalSequence_termFirstThenKill() {
        XCTAssertEqual(PortKillStrategy.signal(atStage: 0), SIGTERM)
        XCTAssertEqual(PortKillStrategy.signal(atStage: 1), SIGKILL)
        XCTAssertEqual(PortKillStrategy.signal(atStage: 2), SIGKILL, "越界阶段兜底 SIGKILL")
    }

    func test_graceConstants() {
        XCTAssertEqual(PortKillStrategy.graceNanos, 2_000_000_000, "SIGTERM 宽限期 2 秒")
        XCTAssertEqual(PortKillStrategy.pollIntervalNanos, 200_000_000)
    }
}
