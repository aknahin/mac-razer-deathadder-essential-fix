import Foundation
import Network
import RazerKit

/// A tiny HTTP/1.1 server bound to 127.0.0.1 that serves the web UI and a JSON API.
///
/// Every `/api/*` request must carry the per-launch token in an `X-Token` header,
/// so other websites open in the browser can't drive the mouse.
final class WebServer {
    let port: UInt16
    let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "deathadder-fix.http")
    /// Serialises all USB traffic.
    private let deviceQueue = DispatchQueue(label: "deathadder-fix.device")
    private let webRoot: URL

    init(port: UInt16) {
        self.port = port
        // Inside the .app the files live in Contents/Resources/Web; from `swift run` they live in the SwiftPM bundle.
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Web"), FileManager.default.fileExists(atPath: r.path) {
            webRoot = r
        } else {
            webRoot = Bundle.module.resourceURL!.appendingPathComponent("Web")
        }
    }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        listener.start(queue: queue)
        self.listener = listener
    }

    // MARK: - HTTP plumbing

    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            guard let self, error == nil else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if let req = Self.parse(buf) {
                self.route(req) { status, type, body in self.respond(conn, status: status, type: type, body: body) }
            } else if done || buf.count > 1_000_000 {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private static func parse(_ data: Data) -> Request? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[headerEnd.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(parts[0]), path: String(parts[1]), headers: headers, body: Data(body.prefix(length)))
    }

    private func respond(_ conn: NWConnection, status: Int, type: String, body: Data) {
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 500: "Internal Server Error", 503: "Service Unavailable"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - Routing

    private typealias Reply = (Int, String, Data) -> Void

    private func route(_ req: Request, reply: @escaping Reply) {
        let path = String(req.path.split(separator: "?", maxSplits: 1).first ?? "/")
        if path.hasPrefix("/api/") {
            // Host check blocks DNS rebinding; token check blocks other sites.
            let host = req.headers["host"] ?? ""
            guard host == "127.0.0.1:\(port)" || host == "localhost:\(port)",
                  req.headers["x-token"] == token else {
                return json(reply, 403, ["error": "forbidden"])
            }
            deviceQueue.async { self.api(req.method, path, req.body, reply) }
        } else {
            serveFile(path == "/" ? "/index.html" : path, reply)
        }
    }

    private func serveFile(_ path: String, _ reply: Reply) {
        let file = webRoot.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(webRoot.standardizedFileURL.path), let data = try? Data(contentsOf: file) else {
            return reply(404, "text/plain", Data("Not found".utf8))
        }
        let types = ["html": "text/html; charset=utf-8", "css": "text/css", "js": "text/javascript",
                     "svg": "image/svg+xml", "png": "image/png", "ico": "image/x-icon"]
        reply(200, types[file.pathExtension] ?? "application/octet-stream", data)
    }

    private func json(_ reply: Reply, _ status: Int, _ object: Any) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        reply(status, "application/json", data)
    }

    // MARK: - API

    private func api(_ method: String, _ path: String, _ body: Data, _ reply: @escaping Reply) {
        let input = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        if method == "POST", path == "/api/quit" {
            json(reply, 200, ["quitting": true])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
            return
        }
        do {
            let mouse = try DeathAdderEssential.open()
            switch (method, path) {
            case ("GET", "/api/status"):
                break
            case ("POST", "/api/fix"):
                try mouse.fixSideButtons()
            case ("POST", "/api/reset"):
                try mouse.resetAll()
            case ("POST", "/api/assign"):
                guard let name = input["button"] as? String, let button = MouseButton(name: name),
                      button != .left, button != .right,
                      let action = Self.action(from: input) else {
                    return json(reply, 400, ["error": "Invalid button or action."])
                }
                try mouse.setAction(action, for: button)
            default:
                return json(reply, 404, ["error": "unknown endpoint"])
            }
            json(reply, 200, try Self.status(of: mouse))
        } catch RazerError.notConnected {
            json(reply, 200, ["connected": false])
        } catch {
            json(reply, 500, ["connected": true, "error": "\(error)"])
        }
    }

    /// `{"type":"mouse","value":4}`, `{"type":"disabled"}` or `{"type":"keyboard","modifiers":8,"usage":47}`
    private static func action(from input: [String: Any]) -> ButtonAction? {
        switch input["type"] as? String {
        case "disabled": return .disabled
        case "mouse":
            guard let v = input["value"] as? Int, (1...5).contains(v) else { return nil }
            return .mouseButton(UInt8(v))
        case "keyboard":
            guard let m = input["modifiers"] as? Int, let u = input["usage"] as? Int,
                  (0...0x0f).contains(m), (0x04...0xe7).contains(u) else { return nil }
            return .keyboard(modifiers: KeyModifiers(rawValue: UInt8(m)), usage: UInt8(u))
        default: return nil
        }
    }

    private static func status(of mouse: DeathAdderEssential) throws -> [String: Any] {
        var buttons: [String: Any] = [:]
        for (b, a) in try mouse.allActions() {
            var entry: [String: Any] = ["label": Shortcut.describe(a)]
            switch a {
            case .disabled: entry["type"] = "disabled"
            case .mouseButton(let n): entry["type"] = "mouse"; entry["value"] = Int(n)
            case .keyboard(let m, let u): entry["type"] = "keyboard"; entry["modifiers"] = Int(m.rawValue); entry["usage"] = Int(u)
            case .unknown: entry["type"] = "unknown"
            }
            buttons[b.name] = entry
        }
        return ["connected": true, "firmware": try mouse.firmwareVersion(),
                "mode": Int(try mouse.deviceMode()), "buttons": buttons]
    }
}
