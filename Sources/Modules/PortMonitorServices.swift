import Foundation

// 端口占用的查询与终止服务（依赖全注入，编入测试目标）。
// 运行时模块壳见 Sources/App/PortMonitor/PortMonitorModule.swift。

/// 端口占用查询范围。
enum PortQueryMode: Equatable {
    /// 仅监听（TCP LISTEN + 全部 UDP）
    case listening
    /// 全部 TCP/UDP 连接
    case all

    var lsofArguments: [String] {
        switch self {
        case .listening: return ["-nP", "-iTCP", "-sTCP:LISTEN", "-iUDP"]
        case .all: return ["-nP", "-iTCP", "-iUDP"]
        }
    }
}

/// 执行 /usr/sbin/lsof 并解析为占用记录（后台执行，主线程回调）。
final class PortQueryService {
    enum QueryError: LocalizedError {
        case lsofUnavailable
        case lsofFailed(status: Int32)

        var errorDescription: String? {
            switch self {
            case .lsofUnavailable: return "lsof 不可用（/usr/sbin/lsof）"
            case .lsofFailed(let status): return "lsof 执行失败（退出码 \(status)）"
            }
        }
    }

    /// 进程执行注入点（测试用）。默认真实 Process，返回 (stdout, 退出码)；启动失败返回 nil。
    var runner: ([String]) -> (data: Data, status: Int32)? = { args in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (data, process.terminationStatus)
    }

    func query(mode: PortQueryMode, completion: @escaping (Result<[PortProcessEntry], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let outcome = runner(mode.lsofArguments)
            guard let result = outcome, result.status == 0 else {
                let error: Error = outcome.map { QueryError.lsofFailed(status: $0.status) } ?? QueryError.lsofUnavailable
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let output = String(data: result.data, encoding: .utf8) ?? ""
            let entries = PortQueryParser.parse(output, currentUserName: NSUserName())
            DispatchQueue.main.async { completion(.success(entries)) }
        }
    }
}

/// 终止进程：SIGTERM 宽限 2 秒 → SIGKILL 兜底（PortKillStrategy）。仅当前用户进程可杀。
final class PortKillService {
    enum KillError: LocalizedError, Equatable {
        case notCurrentUser
        case permissionDenied
        case stillAlive

        var errorDescription: String? {
            switch self {
            case .notCurrentUser: return "只能结束当前用户的进程"
            case .permissionDenied: return "无权限结束该进程（可能需要 root）"
            case .stillAlive: return "进程未能终止"
            }
        }
    }

    /// 测试注入点：存活探测（默认 kill(pid, 0) == 0）。
    var isAlive: (Int32) -> Bool = { pid in Darwin.kill(pid, 0) == 0 }
    /// 测试注入点：发信号（默认 kill(pid, sig) == 0）。
    var send: (Int32, Int32) -> Bool = { pid, sig in Darwin.kill(pid, sig) == 0 }
    /// 测试注入点：睡眠。
    var sleep: (UInt64) -> Void = { nanos in Thread.sleep(forTimeInterval: Double(nanos) / 1_000_000_000) }
    /// 测试注入点：errno 读取。
    var currentErrno: () -> Int32 = { errno }

    func kill(entry: PortProcessEntry, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            guard entry.isCurrentUser else {
                DispatchQueue.main.async { completion(.failure(KillError.notCurrentUser)) }
                return
            }
            let pid = Int32(entry.pid)
            // 快照到点击之间进程可能已自行退出：直接判成功，不发信号
            guard isAlive(pid) else {
                DispatchQueue.main.async { completion(.success(())) }
                return
            }
            guard send(pid, PortKillStrategy.signal(atStage: 0)) else {
                // ESRCH = 发送瞬间进程已不在（退出竞态），同样视为成功
                if currentErrno() == ESRCH {
                    DispatchQueue.main.async { completion(.success(())) }
                } else {
                    let error: Error = currentErrno() == EPERM ? KillError.permissionDenied : KillError.stillAlive
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
                return
            }
            if awaitExit(pid, within: PortKillStrategy.graceNanos) {
                DispatchQueue.main.async { completion(.success(())) }
                return
            }
            if !send(pid, PortKillStrategy.signal(atStage: 1)), currentErrno() != ESRCH {
                DispatchQueue.main.async { completion(.failure(KillError.stillAlive)) }
                return
            }
            if awaitExit(pid, within: 1_000_000_000) {
                DispatchQueue.main.async { completion(.success(())) }
                return
            }
            DispatchQueue.main.async { completion(.failure(KillError.stillAlive)) }
        }
    }

    /// 轮询存活直到退出或超时；进程本就不存在视为已退出。
    private func awaitExit(_ pid: Int32, within nanos: UInt64) -> Bool {
        var waited = UInt64(0)
        while waited < nanos {
            if !isAlive(pid) { return true }
            sleep(PortKillStrategy.pollIntervalNanos)
            waited += PortKillStrategy.pollIntervalNanos
        }
        return !isAlive(pid)
    }
}
