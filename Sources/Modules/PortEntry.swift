import Foundation

/// 一条端口占用记录：监听/连接的 (端口, 协议, PID, 进程, 用户)。
public struct PortProcessEntry: Equatable {
    public let port: Int
    /// "TCP" / "UDP"
    public let protocolName: String
    public let pid: Int
    public let processName: String
    public let user: String
    /// lsof NAME 列（如 "*:3000"、"127.0.0.1:8080"、"[::]:3000"），不含状态后缀。
    public let address: String
    /// TCP 状态（LISTEN/ESTABLISHED...）；UDP 无状态为 ""。
    public let state: String
    /// 是否当前用户进程（他人/root 进程 UI 灰显、不可杀）。
    public let isCurrentUser: Bool

    public init(port: Int, protocolName: String, pid: Int, processName: String,
                user: String, address: String, state: String, isCurrentUser: Bool) {
        self.port = port
        self.protocolName = protocolName
        self.pid = pid
        self.processName = processName
        self.user = user
        self.address = address
        self.state = state
        self.isCurrentUser = isCurrentUser
    }
}

/// lsof 输出 → 占用记录。纯函数，TDD。
/// 输入为 `lsof -nP -iTCP ... -iUDP` 的原始 stdout（首行为表头）。
public enum PortQueryParser {

    /// - Parameters:
    ///   - lsofOutput: 原始输出。
    ///   - currentUserName: 当前用户名（NSUserName()），决定 isCurrentUser。
    public static func parse(_ lsofOutput: String, currentUserName: String?) -> [PortProcessEntry] {
        var entries: [PortProcessEntry] = []
        var seen = Set<String>()
        for rawLine in lsofOutput.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME[(STATE)]
            guard cols.count >= 9 else { continue }
            guard cols[0] != "COMMAND" else { continue }        // 表头
            guard let pid = Int(cols[1]) else { continue }      // 表头/异常行
            let processName = cols[0]
            let user = cols[2]
            let proto = cols[7]
            guard proto == "TCP" || proto == "UDP" else { continue }

            // NAME 与可能的状态后缀（" (LISTEN)" 等）拼回后拆分
            let nameAndState = cols[8...].joined(separator: " ")
            var address = nameAndState
            var state = ""
            if nameAndState.hasSuffix(")"), let open = nameAndState.lastIndex(of: "(") {
                state = String(nameAndState[nameAndState.index(after: open)..<nameAndState.index(before: nameAndState.endIndex)])
                address = String(nameAndState[..<open]).trimmingCharacters(in: .whitespaces)
            }
            // 端口号取本地端（ESTABLISHED 的 NAME 是 "本地->远端"），支持
            // *:3000 / [::]:3000 / 127.0.0.1:8080
            let localAddress = address.split(separator: "->", maxSplits: 1).first.map(String.init) ?? address
            guard let port = portNumber(from: localAddress) else { continue }

            // IPv4+IPv6 双栈监听同一端口去重为一行
            let key = "\(port)|\(proto)|\(pid)|\(state)"
            guard seen.insert(key).inserted else { continue }

            entries.append(PortProcessEntry(
                port: port, protocolName: proto, pid: pid,
                processName: processName, user: user,
                address: address, state: state,
                isCurrentUser: currentUserName.map { $0 == user } ?? false))
        }
        return entries
    }

    /// 地址末段端口号：`*:3000` / `[::]:3000` / `127.0.0.1:8080` 都取最后一个冒号后的数字。
    static func portNumber(from address: String) -> Int? {
        guard let idx = address.lastIndex(of: ":") else { return nil }
        return Int(address[address.index(after: idx)...])
    }
}

/// 列表过滤：仅监听 + 搜索。纯函数，TDD。
public struct PortListFilter: Equatable {
    public var listenOnly: Bool
    public var searchText: String

    public init(listenOnly: Bool = true, searchText: String = "") {
        self.listenOnly = listenOnly
        self.searchText = searchText
    }

    /// listenOnly 语义：TCP 取 LISTEN；UDP 无连接状态（绑定即监听），全部保留。
    public func apply(_ entries: [PortProcessEntry]) -> [PortProcessEntry] {
        var result = entries
        if listenOnly {
            result = result.filter { $0.protocolName == "UDP" || $0.state == "LISTEN" }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return result }
        let lowered = query.lowercased()
        return result.filter {
            $0.processName.lowercased().contains(lowered)
                || String($0.port).contains(query)
                || String($0.pid).contains(query)
        }
    }
}

/// kill 终止序列：SIGTERM 优先给优雅退出机会，超过宽限期仍存活才 SIGKILL。
public enum PortKillStrategy {
    /// 宽限期（纳秒）：SIGTERM 后等待进程自行退出。
    public static let graceNanos: UInt64 = 2_000_000_000
    /// 存活轮询间隔（纳秒）。
    public static let pollIntervalNanos: UInt64 = 200_000_000
    /// 第 stage 步应发的信号：0 = SIGTERM，≥1 = SIGKILL。
    public static func signal(atStage stage: Int) -> Int32 {
        stage == 0 ? SIGTERM : SIGKILL
    }
}
