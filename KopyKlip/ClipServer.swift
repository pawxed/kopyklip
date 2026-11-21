import Foundation
import Network

final class ClipServer {
    static let shared = ClipServer()

    private var listener: NWListener?

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: ClipBridge.port) else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            ClipServer.respond(on: connection)
        }
        listener.start(queue: .global())
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private static func respond(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
            let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            if let components = URLComponents(string: "http://localhost\(target)") {
                let id = components.queryItems?.first { $0.name == "id" }?.value
                switch components.path {
                case "/delete":
                    if let id, let uuid = UUID(uuidString: id) {
                        KopyStore.removeClip(id: uuid)
                    }
                case "/clear":
                    KopyStore.clearClips()
                default:
                    break
                }
            }
            let clips = KopyStore.clips().filter { !$0.isImage }
            let body = (try? JSONEncoder().encode(clips)) ?? Data("[]".utf8)
            var response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
