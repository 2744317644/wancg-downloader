import CFNetwork
import Foundation
import Network

final class LocalProxy {
    static let shared = LocalProxy()

    private let queue = DispatchQueue(label: "wnacg.local-proxy")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var started = false

    private init() {}

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        started = false
        port = 0
    }

    func start() throws -> UInt16 {
        if started { return port }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1", port: .any
        )
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener

        let semaphore = DispatchSemaphore(value: 0)
        var startup: Result<UInt16, Error>?
        var signaled = false

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard !signaled else { return }
                signaled = true
                if let value = listener.port?.rawValue {
                    startup = .success(value)
                } else {
                    startup = .failure(WnacgError.message("本地代理端口不可用"))
                }
                semaphore.signal()
            case .failed(let error):
                guard !signaled else { return }
                signaled = true
                startup = .failure(error)
                semaphore.signal()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)

        if semaphore.wait(timeout: .now() + 5) == .timedOut {
            listener.cancel()
            throw WnacgError.message("本地代理启动超时")
        }
        guard let result = startup else {
            listener.cancel()
            throw WnacgError.message("本地代理启动失败")
        }
        switch result {
        case .success(let value):
            port = value
            started = true
            return value
        case .failure(let error):
            listener.cancel()
            throw error
        }
    }

    private func handle(_ client: NWConnection) {
        client.start(queue: queue)
        receiveHeaders(client, buffer: Data())
    }

    private func receiveHeaders(_ client: NWConnection, buffer: Data) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 16384) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data, !data.isEmpty {
                buffer.append(data)
            }

            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                let leftover = Data(buffer[range.upperBound...])
                self.handleConnect(header, client: client, leftover: leftover)
                return
            }
            if isComplete || error != nil || buffer.count > 32768 {
                client.cancel()
                return
            }
            self.receiveHeaders(client, buffer: buffer)
        }
    }

    private func handleConnect(
        _ header: String, client: NWConnection, leftover: Data
    ) {
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendError(client, "400 Bad Request")
            return
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0].uppercased() == "CONNECT" else {
            sendError(client, "405 Method Not Allowed")
            return
        }
        let hostPort = String(parts[1])
        guard let colon = hostPort.lastIndex(of: ":") else {
            sendError(client, "400 Bad Request")
            return
        }
        let host = String(hostPort[..<colon])
        let portText = String(hostPort[hostPort.index(after: colon)...])
        guard let targetPort = UInt16(portText) else {
            sendError(client, "400 Bad Request")
            return
        }

        Task {
            do {
                let ips = try await DoHResolver.shared.resolve(host: host)
                self.queue.async {
                    self.connect(
                        ips: ips,
                        port: targetPort,
                        client: client,
                        leftover: leftover,
                        index: 0
                    )
                }
            } catch {
                self.queue.async {
                    self.sendError(client, "502 Bad Gateway")
                }
            }
        }
    }

    private func connect(
        ips: [String],
        port: UInt16,
        client: NWConnection,
        leftover: Data,
        index: Int
    ) {
        guard index < ips.count,
              let endpointPort = NWEndpoint.Port(rawValue: port) else {
            sendError(client, "502 Bad Gateway")
            return
        }

        let server = NWConnection(
            host: NWEndpoint.Host(ips[index]),
            port: endpointPort,
            using: .tcp
        )
        var advanced = false

        server.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard !advanced else { return }
                advanced = true
                self.establish(client: client, server: server, leftover: leftover)
            case .failed, .cancelled:
                guard !advanced else { return }
                advanced = true
                server.cancel()
                self.connect(
                    ips: ips,
                    port: port,
                    client: client,
                    leftover: leftover,
                    index: index + 1
                )
            default:
                break
            }
        }
        server.start(queue: queue)
    }

    private func establish(
        client: NWConnection, server: NWConnection, leftover: Data
    ) {
        let response = Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)
        client.send(content: response, completion: .contentProcessed {
            [weak self] error in
            guard let self else { return }
            if error != nil {
                client.cancel()
                server.cancel()
                return
            }
            if leftover.isEmpty {
                self.pump(client, to: server)
                self.pump(server, to: client)
            } else {
                server.send(content: leftover, completion: .contentProcessed { sendError in
                    if sendError != nil {
                        client.cancel()
                        server.cancel()
                        return
                    }
                    self.pump(client, to: server)
                    self.pump(server, to: client)
                })
            }
        })
    }

    private func pump(_ from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil || isComplete || error != nil {
                        from.cancel()
                        to.cancel()
                        return
                    }
                    self.pump(from, to: to)
                })
            } else if isComplete || error != nil {
                from.cancel()
                to.cancel()
            } else {
                self.pump(from, to: to)
            }
        }
    }

    private func sendError(_ client: NWConnection, _ status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        client.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            client.cancel()
        })
    }
}

final class ProxySession {
    static let shared = ProxySession()

    private(set) var session: URLSession
    private(set) var startupError: Error?
    private(set) var proxyPort: UInt16 = 0

    private init() {
        session = URLSession(configuration: .default)
        rebuild(invalidate: false)
    }

    /// 回到前台后旧端口/旧连接可能已经失效，重建监听和 URLSession。
    func restart() {
        LocalProxy.shared.stop()
        rebuild(invalidate: true)
    }

    private func rebuild(invalidate: Bool) {
        if invalidate {
            session.invalidateAndCancel()
        }
        do {
            let port = try LocalProxy.shared.start()
            proxyPort = port
            startupError = nil
            session = ProxySession.makeSession(port: port)
        } catch {
            startupError = error
            proxyPort = 0
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 1200
            session = URLSession(configuration: configuration)
        }
    }

    private static func makeSession(port: UInt16) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.connectionProxyDictionary = [
            "HTTPEnable": true,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": Int(port),
            "HTTPSEnable": true,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": Int(port),
        ]
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1200
        return URLSession(configuration: configuration)
    }
}
