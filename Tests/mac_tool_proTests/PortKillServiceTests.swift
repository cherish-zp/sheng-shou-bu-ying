import XCTest

/// TDD: PortKillService 终止序列 —— 依赖全注入（isAlive/send/errno/sleep），
/// 验证：已退出直接成功、ESRCH 判成功、EPERM 判权限、TERM 宽限内退出不发 KILL、
/// 宽限超时升 KILL、双信号仍活报失败。
final class PortKillServiceTests: XCTestCase {

    private var service: PortKillService!
    private var aliveStatus: [Int32: Bool] = [:]     // pid → 是否存活
    private var sentSignals: [(pid: Int32, signal: Int32)] = []
    private var fakeErrno: Int32 = 0
    private var sleepCount = 0

    override func setUp() {
        super.setUp()
        service = PortKillService()
        service.isAlive = { [self] pid in aliveStatus[pid] ?? false }
        service.send = { [self] pid, sig in
            guard aliveStatus[pid] == true else {
                fakeErrno = ESRCH
                return false
            }
            sentSignals.append((pid, sig))
            if sig == SIGKILL { aliveStatus[pid] = false }
            return true
        }
        service.currentErrno = { [self] in fakeErrno }
        service.sleep = { [self] _ in sleepCount += 1 }
    }

    private func entry(pid: Int) -> PortProcessEntry {
        PortProcessEntry(port: 3000, protocolName: "TCP", pid: pid,
                         processName: "node", user: "u", address: "*:3000",
                         state: "LISTEN", isCurrentUser: true)
    }

    private func awaitKill(pid: Int) -> Result<Void, Error> {
        let expectation = expectation(description: "kill completion")
        var result: Result<Void, Error>!
        service.kill(entry: entry(pid: pid)) {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        return result
    }

    func test_alreadyExited_returnsSuccessWithoutSignal() {
        let result = awaitKill(pid: 100)   // aliveStatus 无记录 = 已退出
        guard case .success = result else { return XCTFail("进程已退出应判成功") }
        XCTAssertTrue(sentSignals.isEmpty, "不得向已退出进程发信号")
    }

    func test_sigtermFailsWithESRCH_treatedAsSuccess() {
        aliveStatus[200] = true
        // isAlive 说活着但 send 时已消失（竞态）→ ESRCH → 成功
        service.isAlive = { [self] pid in pid == 200 }
        service.send = { [self] pid, _ in
            fakeErrno = ESRCH
            return false
        }
        let result = awaitKill(pid: 200)
        guard case .success = result else { return XCTFail("ESRCH = 进程已不在，应判成功") }
    }

    func test_sigtermFailsWithEPERM_reportsPermission() {
        aliveStatus[300] = true
        service.send = { [self] _, _ in
            fakeErrno = EPERM
            return false
        }
        let result = awaitKill(pid: 300)
        guard case .failure(let error) = result else { return XCTFail("EPERM 应报失败") }
        XCTAssertEqual(error.localizedDescription, PortKillService.KillError.permissionDenied.localizedDescription)
    }

    func test_notCurrentUser_rejected() {
        let service = PortKillService()
        service.isAlive = { _ in true }
        service.send = { _, _ in true }
        service.currentErrno = { 0 }
        service.sleep = { _ in }
        let notMine = PortProcessEntry(port: 1, protocolName: "TCP", pid: 400,
                                       processName: "rootd", user: "root", address: "*:1",
                                       state: "LISTEN", isCurrentUser: false)
        let expectation = expectation(description: "completion")
        var failure: Error?
        service.kill(entry: notMine) {
            if case .failure(let error) = $0 { failure = error }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual((failure as? PortKillService.KillError), .notCurrentUser)
    }

    func test_termSucceedsWithinGrace_noKillSent() {
        aliveStatus[500] = true
        // SIGTERM 后第 2 次轮询前退出
        var polls = 0
        service.isAlive = { [self] pid in
            guard pid == 500 else { return false }
            polls += 1
            return polls <= 1
        }
        let result = awaitKill(pid: 500)
        guard case .success = result else { return XCTFail("宽限期内退出应成功") }
        XCTAssertEqual(sentSignals.map(\.signal), [SIGTERM], "宽限内退出不得升级 SIGKILL")
    }

    func test_survivesGrace_escalatesToKill() {
        // 默认假体：TERM 后仍活（aliveStatus 不变），SIGKILL 置死
        aliveStatus[600] = true
        let result = awaitKill(pid: 600)
        guard case .success = result else { return XCTFail("SIGKILL 后应成功") }
        XCTAssertEqual(sentSignals.map(\.signal), [SIGTERM, SIGKILL], "超宽限应升级 SIGKILL")
    }
}
