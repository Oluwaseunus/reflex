import Foundation
import Network

/// One-shot HTTP listener on a loopback port used for receiving the OAuth
/// authorization-code callback (RFC 8252). Starts on one of the
/// caller-provided ports, waits for the browser's GET, returns a "you can
/// close this window" HTML response, and shuts down.
final class LoopbackCallbackServer {
    enum CallbackError: Error {
        case allPortsInUse
        case timedOut
        case listenerFailed(Error)
    }

    private var listener: NWListener?
    private var completion: ((Result<URL, CallbackError>) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var boundPort: UInt16 = 0
    private var expectedState: String = ""
    private let queue = DispatchQueue(label: "com.reflex.app.spotify-auth-callback")

    /// Start listening on the first available port in `preferredPorts`.
    /// Returns the bound port. Completion fires once — with the full callback
    /// URL on success, or an error on timeout / bind failure.
    ///
    /// `expectedState` is the OAuth `state` value from the authorize URL.
    /// Callback requests whose state doesn't match are treated as 404 so the
    /// listener keeps waiting for Spotify's real redirect — without this, any
    /// local process that happened to POST `?code=x&state=y` could burn the
    /// one-shot auth attempt even with valid-looking params.
    func start(
        preferredPorts: [UInt16],
        expectedState: String,
        timeout: TimeInterval,
        completion: @escaping (Result<URL, CallbackError>) -> Void
    ) -> UInt16? {
        for port in preferredPorts {
            if tryBind(port: port) {
                self.completion = completion
                self.boundPort = port
                self.expectedState = expectedState
                scheduleTimeout(timeout)
                return port
            }
        }
        completion(.failure(.allPortsInUse))
        return nil
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        listener?.cancel()
        listener = nil
        expectedState = ""
        boundPort = 0
    }

    private func tryBind(port: UInt16) -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        // Loopback-only: requiredInterfaceType = .loopback means the listener
        // is not reachable from other hosts on the network, even if the port
        // is otherwise routable.
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback

        do {
            let listener = try NWListener(using: params, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.finish(with: .failure(.listenerFailed(error)))
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            return true
        } catch {
            return false
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            // We only care about the request line: "GET /callback?... HTTP/1.1".
            // Parse out the path + query; compose a full URL with our bound
            // host so URLComponents can decode the query items.
            let path = Self.parseRequestPath(from: data) ?? "/"
            let urlString = "http://127.0.0.1:\(self.boundPort)\(path)"
            let url = URL(string: urlString)

            // Only treat requests that target our callback path, carry a
            // usable OAuth payload, *and* match the state we issued as the one
            // that ends the flow. Anything else (favicon probes, browser
            // prefetches, local scanners, a same-machine process trying to
            // race Spotify with forged params) gets a 404 and the listener
            // keeps waiting for the real Spotify redirect.
            let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            let isCallback = components?.path == Constants.Spotify.callbackPath
            let items = components?.queryItems ?? []
            let hasCode = items.contains(where: { $0.name == "code" && ($0.value?.isEmpty == false) })
            let hasError = items.contains(where: { $0.name == "error" && ($0.value?.isEmpty == false) })
            let stateValue = items.first(where: { $0.name == "state" })?.value ?? ""
            let stateMatches = !self.expectedState.isEmpty && stateValue == self.expectedState
            let isOAuthCallback = isCallback && stateMatches && (hasCode || hasError)

            if isOAuthCallback, let url {
                let body = Self.pageHTML(for: url)
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                self.finish(with: .success(url))
            } else {
                let body = "Not Found"
                let response = "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private static func pageHTML(for url: URL?) -> String {
        let items = url
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
            .flatMap(\.queryItems) ?? []
        let code = items.first(where: { $0.name == "code" })?.value
        let error = items.first(where: { $0.name == "error" })?.value

        let heading: String
        let message: String
        let accent: String
        if let error {
            accent = "#c0392b"
            switch error {
            case "access_denied":
                heading = "Sign-in cancelled"
                message = "You can close this window and try again when you're ready."
            default:
                heading = "Sign-in failed"
                // error codes are short ASCII; escape just in case.
                message = "Spotify returned: \(Self.escapeHTML(error)). You can close this window and try again."
            }
        } else if code != nil {
            accent = "#1db954"
            heading = "Signed in to Reflex"
            message = "You can close this window."
        } else {
            accent = "#c0392b"
            heading = "Sign-in failed"
            message = "The callback didn't include an authorization code. You can close this window and try again."
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>Reflex</title>
        </head>
        <body style="font-family:-apple-system,sans-serif;text-align:center;padding:48px;color:#222;">
            <h2 style="color:\(accent);margin-bottom:12px;">\(heading)</h2>
            <p>\(message)</p>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func parseRequestPath(from data: Data?) -> String? {
        guard let data, let raw = String(data: data, encoding: .utf8) else { return nil }
        let firstLine = raw.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }

    private func scheduleTimeout(_ timeout: TimeInterval) {
        timeoutTask = Task { [weak self, queue] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if Task.isCancelled { return }
            // Hop to the listener queue so finish(with:) races against
            // success/failure deliveries serially, not concurrently.
            queue.async { self?.finish(with: .failure(.timedOut)) }
        }
    }

    /// Must be called on `queue`. Idempotent: the first result wins, later
    /// calls are dropped — prevents the timeout from overwriting an in-flight
    /// success delivery (or vice versa).
    private func finish(with result: Result<URL, CallbackError>) {
        guard let c = completion else { return }
        completion = nil
        stop()
        // Dispatch completion on main so the caller doesn't have to bounce.
        DispatchQueue.main.async { c(result) }
    }
}
