import AppKit
import Foundation

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
    enum KillError: LocalizedError {
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
            guard send(pid, PortKillStrategy.signal(atStage: 0)) else {
                let error: Error = currentErrno() == EPERM ? KillError.permissionDenied : KillError.stillAlive
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            if awaitExit(pid, within: PortKillStrategy.graceNanos) {
                DispatchQueue.main.async { completion(.success(())) }
                return
            }
            _ = send(pid, PortKillStrategy.signal(atStage: 1))
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

/// 端口占用模块：F2 / 菜单点击打开占用窗口。
final class PortMonitorModule: NSObject, AppModule {
    let id = "portMonitor"
    let title = "端口占用"
    /// F2：唯一未占用的功能键（F1 截图/F3 贴图/F4 录屏/F5 取色/F6 恢复贴图）。
    let defaultHotkey = Hotkey(keyCode: 120)

    private let queryService = PortQueryService()
    private let killService = PortKillService()
    private var windowController: PortListWindowController?

    func perform() {
        let controller = windowController ?? PortListWindowController(
            queryService: queryService, killService: killService)
        windowController = controller
        controller.showAndRefresh()
    }

    func stop() {
        // 模块停用：收起窗口（重新启用后菜单/热键可再呼出）
        windowController?.window.orderOut(nil)
    }
}
