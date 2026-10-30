import Foundation
import Network

/// 手机遥控：本地网络 HTTP 服务（Bonjour 发布 _shoushou._tcp），
/// 手机浏览器/快捷指令访问 http://<mac-ip>:<port>/action/screenshot 触发动作。
final class RemoteControlServer: NSObject {
    static let shared = RemoteControlServer()
    private var listener: NWListener?
    var onAction: ((String) -> Void)?

    /// 指令名 → 可触发动作白名单。
    private let actions = ["screenshot", "lock", "reveal-desktop", "start-recording", "stop-recording"]

    func start(port: UInt16 = 18777) {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        guard let portValue = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: params, on: portValue) else {
            DiagLog.write("RemoteControl: 端口 \(port) 监听失败")
            return
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: DispatchQueue.global(qos: .utility))
        // Bonjour 发布
        listener.service = NWListener.Service(name: "圣手捕影遥控", type: "_http._tcp.", domain: nil, txtRecord: nil)
        DiagLog.write("RemoteControl: listening on \(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        receive(connection)
    }

    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            // GET /action/<name>
            guard let path = request.split(separator: "\r\n").first,
                  let start = path.range(of: "GET /action/"),
                  let action = path[start.upperBound...].split(separator: " ").first.map(String.init),
                  self.actions.contains(action) else {
                self.respond(connection, status: "404 Not Found", body: "unknown")
                return
            }
            DispatchQueue.main.async {
                switch action {
                case "screenshot": self.onAction?("screenshot")
                case "lock": self.onAction?("lock")
                case "reveal-desktop": self.onAction?("reveal-desktop")
                case "start-recording": self.onAction?("start-recording")
                case "stop-recording": self.onAction?("stop-recording")
                default: break
                }
            }
            self.respond(connection, status: "200 OK", body: "ok")
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
