import Foundation

private final class MessagesTransferProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    static var handler: ((URLRequest, Int) -> (Int, Data))!
    static var delay = 0.0
    private var cancelled = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, data) = Self.handler(request, Self.requests.count)
        let finish = {
            guard !self.cancelled else { return }
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if Self.delay == 0 { finish() }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: finish) }
    }
    override func stopLoading() { cancelled = true }
}

@main
enum MessagesCookieTransferTests {
    @MainActor
    static func main() async throws {
        let base = URL(string: "https://messages-transfer.test")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MessagesTransferProtocol.self]
        let session = URLSession(configuration: configuration)
        let suite = "MessagesTransferTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); session.invalidateAndCancel() }
        let completedKey = "LastTransferredHNAuthFingerprint"
        let prepared = PreparedTransfer(sessionId: "session-one", token: "test-card-token", inspectorURL: nil)
        func json(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
        func receipt(_ id: String = "session-one", count: Int = 1) -> Data {
            json(["ok": true, "sessionId": id, "injected": count])
        }
        func cookie(_ value: String = "test-session", domain: String = "news.ycombinator.com") -> HTTPCookie {
            HTTPCookie(properties: [.name: "user", .value: value, .domain: domain, .path: "/",
                HTTPCookiePropertyKey("HttpOnly"): "TRUE", .secure: "TRUE"])!
        }
        func make(_ secret: String? = String(repeating: "x", count: 32)) -> MessagesCookieTransfer {
            MessagesCookieTransfer(baseURL: base, clientSecret: secret, session: session,
                defaults: defaults, retryDelay: 1_000_000)
        }
        func resetRequests() {
            defaults.removePersistentDomain(forName: suite)
            MessagesTransferProtocol.requests = []
            MessagesTransferProtocol.delay = 0
        }
        func settle(_ transfer: MessagesCookieTransfer) async throws {
            for _ in 0..<300 {
                switch transfer.state {
                case .sending, .retrying: try await Task.sleep(nanoseconds: 10_000_000)
                default: return
                }
            }
            preconditionFailure("Transfer did not settle")
        }
        func requestBody(_ request: URLRequest) -> [String: Any] {
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            return try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        }
        MessagesTransferProtocol.handler = { request, _ in
            if request.url?.path == "/api/transfers/prepare" {
                precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(String(repeating: "x", count: 32))")
                return (200, json(["ok": true, "sessionId": prepared.sessionId, "token": prepared.token]))
            }
            precondition(request.url == base.appendingPathComponent("api/cookies"))
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(prepared.token)")
            let cookies = requestBody(request)["cookies"] as! [[String: Any]]
            precondition(cookies.count == 1 && cookies[0]["httpOnly"] as? Bool == true)
            return (200, receipt())
        }
        let transfer = make()
        transfer.cookiesChanged([cookie()])
        precondition(MessagesTransferProtocol.requests.isEmpty && transfer.state == .idle)
        transfer.setEnabled(true)
        transfer.cookiesChanged([cookie(domain: "evil.example")])
        precondition(MessagesTransferProtocol.requests.isEmpty)
        transfer.cookiesChanged([cookie(), cookie(domain: "evil.example")])
        try await settle(transfer)
        precondition(transfer.state == .succeeded(sessionID: "session-one", count: 1))
        precondition(MessagesTransferProtocol.requests.count == 2)
        precondition(defaults.string(forKey: completedKey) != nil)
        transfer.cookiesChanged([cookie()])
        transfer.setEnabled(false)
        transfer.setEnabled(true)
        transfer.cookiesChanged([cookie()])
        precondition(transfer.state == .succeeded(sessionID: "session-one", count: nil))
        precondition(MessagesTransferProtocol.requests.count == 2)

        // A prepared card needs no permanent preparation credential.
        resetRequests()
        MessagesTransferProtocol.handler = { request, _ in
            precondition(request.url?.path == "/api/cookies")
            return (200, receipt())
        }
        let supplied = make(nil)
        supplied.reset(preparation: prepared)
        supplied.setEnabled(true)
        supplied.cookiesChanged([cookie()]); try await settle(supplied)
        precondition(supplied.state == .succeeded(sessionID: "session-one", count: 1))
        precondition(MessagesTransferProtocol.requests.count == 1)

        // Reuse the prepared session through transient upload failures.
        resetRequests()
        MessagesTransferProtocol.handler = { _, attempt in attempt < 3 ? (503, Data()) : (200, receipt()) }
        let retry = make()
        retry.reset(preparation: prepared); retry.setEnabled(true)
        retry.cookiesChanged([cookie()]); try await settle(retry)
        precondition(retry.state == .succeeded(sessionID: "session-one", count: 1))
        precondition(MessagesTransferProtocol.requests.count == 3)

        for failure in [(401, Data()), (200, receipt("wrong-session")), (200, receipt(count: 0)),
                        (200, receipt(count: 2)), (200, json(["ok": true])), (503, Data())] {
            resetRequests()
            MessagesTransferProtocol.handler = { _, _ in failure }
            let rejected = make()
            rejected.reset(preparation: prepared); rejected.setEnabled(true)
            rejected.cookiesChanged([cookie()]); try await settle(rejected)
            guard case .failed = rejected.state else { preconditionFailure("Bad receipt accepted") }
            precondition(MessagesTransferProtocol.requests.count == (failure.0 == 503 ? 3 : 1))
            precondition(defaults.string(forKey: completedKey) == nil)
        }

        // Pausing, switching cards, and logging out all invalidate outstanding responses.
        for action in 0..<3 {
            resetRequests()
            MessagesTransferProtocol.delay = 0.15
            MessagesTransferProtocol.handler = { _, _ in (200, receipt()) }
            let cancelled = make()
            cancelled.reset(preparation: prepared); cancelled.setEnabled(true)
            cancelled.cookiesChanged([cookie()])
            try await Task.sleep(nanoseconds: 20_000_000)
            if action == 0 { cancelled.setEnabled(false) }
            else if action == 1 { cancelled.reset() }
            else { cancelled.cookiesChanged([]) }
            try await Task.sleep(nanoseconds: 200_000_000)
            precondition(cancelled.state == .idle && defaults.string(forKey: completedKey) == nil)
            if action == 0 {
                MessagesTransferProtocol.delay = 0
                cancelled.setEnabled(true)
                cancelled.cookiesChanged([cookie()]); try await settle(cancelled)
                precondition(cancelled.state == .succeeded(sessionID: "session-one", count: 1))
            }
        }

        // Pause during preparation: resuming with a different account must prepare again.
        resetRequests()
        MessagesTransferProtocol.handler = { request, _ in
            if request.url?.path == "/api/transfers/prepare" {
                return (200, json(["ok": true, "sessionId": "session-one", "token": "test-card-token"]))
            }
            return (200, receipt())
        }
        let changed = make()
        changed.setEnabled(true); changed.cookiesChanged([cookie()]); try await settle(changed)
        changed.setEnabled(false); changed.setEnabled(true)
        changed.cookiesChanged([cookie("another-account")]); try await settle(changed)
        precondition(MessagesTransferProtocol.requests.filter { $0.url?.path == "/api/transfers/prepare" }.count == 2)
        print("Messages transfer checks passed: preparation, scoped HttpOnly upload, receipts, deduplication, retries, cancellation, and resume.")
    }
}
