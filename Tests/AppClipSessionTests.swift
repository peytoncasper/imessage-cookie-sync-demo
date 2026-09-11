import Foundation

private final class TransferProtocol: URLProtocol {
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
enum AppClipSessionTests {
    @MainActor
    static func main() async throws {
        let base = URL(string: "https://cookieclip.example")!
        let sid = UUID().uuidString.lowercased()
        let now = Date()
        let claims: [String: Any] = ["s": sid, "i": Int(now.timeIntervalSince1970 * 1000),
                                    "e": Int(now.timeIntervalSince1970 * 1000) + 600_000, "n": "abcdefghijklmnop"]
        let encoded = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let token = "ct1.\(encoded).\(String(repeating: "a", count: 43))"
        var card = URLComponents(url: base.appendingPathComponent("open"), resolvingAgainstBaseURL: false)!
        card.queryItems = [.init(name: "view", value: "web"), .init(name: "target", value: "https://news.ycombinator.com/login"),
                           .init(name: "bbSession", value: sid), .init(name: "bbToken", value: token)]
        let url = card.url!
        let invocation = AppClipInvocation.parse(url, baseURL: base)!
        precondition(invocation.sessionID == sid)
        precondition(AppClipInvocation.parse(url, baseURL: base, now: now.addingTimeInterval(601)) == nil)
        for bad in [
            url.absoluteString + "&bbToken=duplicate", url.absoluteString + "&bbSession=duplicate",
            url.absoluteString + "&unknown=1", url.absoluteString + "#fragment",
            url.absoluteString.replacingOccurrences(of: "https://cookieclip", with: "http://cookieclip"),
            url.absoluteString.replacingOccurrences(of: "https://cookieclip", with: "https://user@cookieclip"),
            url.absoluteString.replacingOccurrences(of: ".example/open", with: ".example:444/open"),
            url.absoluteString.replacingOccurrences(of: "cookieclip.example", with: "evil.example"),
            url.absoluteString.replacingOccurrences(of: "/open?", with: "/other?"),
            url.absoluteString.replacingOccurrences(of: "news.ycombinator.com", with: "evil.example"),
            url.absoluteString.replacingOccurrences(of: "view=web", with: "view=other"),
            url.absoluteString.replacingOccurrences(of: "bbSession=\(sid)", with: "bbSession=\(UUID().uuidString)"),
            url.absoluteString + "&test=" + String(repeating: "a", count: 2048)
        ] { precondition(AppClipInvocation.parse(URL(string: bad)!, baseURL: base) == nil) }
        var apple = card
        apple.host = "appclip.apple.com"; apple.path = "/id"
        apple.queryItems?.append(.init(name: "p", value: "com.example.CookieClipDemo.Clip"))
        precondition(AppClipInvocation.parse(apple.url!, baseURL: base) != nil)
        apple.queryItems?.removeLast()
        apple.queryItems?.append(.init(name: "p", value: "org.anotherteam.Login.Clip"))
        precondition(AppClipInvocation.parse(apple.url!, baseURL: base) == nil)
        precondition(AppClipInvocation.parse(apple.url!, baseURL: base, clipBundleID: "org.anotherteam.Login.Clip") != nil)
        apple.queryItems?.removeLast()
        precondition(AppClipInvocation.parse(apple.url!, baseURL: base) == nil)
        card.queryItems?.removeAll(where: { $0.name == "bbToken" })
        precondition(AppClipInvocation.parse(card.url!, baseURL: base) == nil)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransferProtocol.self]
        let session = URLSession(configuration: configuration)
        let suite = "AppClipTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); session.invalidateAndCancel() }
        func cookie(_ name: String, domain: String = "news.ycombinator.com") -> HTTPCookie {
            HTTPCookie(properties: [.name: name, .value: "test-only", .domain: domain, .path: "/",
                                   .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE"])!
        }
        func response(_ id: String = sid, count: Int = 1) -> Data {
            try! JSONSerialization.data(withJSONObject: ["ok": true, "sessionId": id, "requestId": "test-receipt", "injected": count])
        }
        func coordinator() -> AppClipCookieTransfer {
            AppClipCookieTransfer(invocation: invocation, baseURL: base, session: session, defaults: defaults, retryDelay: 1_000_000)
        }
        func settle(_ transfer: AppClipCookieTransfer) async throws {
            for _ in 0..<300 {
                if transfer.state != .sending { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            preconditionFailure("Transfer did not settle")
        }
        TransferProtocol.handler = { request, _ in
            precondition(request.url == base.appendingPathComponent("api/cookies"))
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count))
                }
            }
            let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
            let cookies = json["cookies"] as! [[String: Any]]
            precondition(cookies.count == 1 && cookies[0]["name"] as? String == "user")
            precondition(cookies[0]["httpOnly"] as? Bool == true)
            return (200, response())
        }
        let transfer = coordinator()
        transfer.cookiesChanged([cookie("other"), cookie("user", domain: "evil.example")])
        precondition(transfer.state == .idle && TransferProtocol.requests.isEmpty)
        transfer.cookiesChanged([cookie("user"), cookie("user", domain: "evil.example")])
        try await settle(transfer)
        guard case .succeeded(let receipt) = transfer.state else { preconditionFailure("Valid transfer failed") }
        precondition(receipt.sessionID == sid && receipt.injected == 1 && receipt.completedAt >= now)
        precondition(defaults.data(forKey: "AppClipLastTransferReceipt") != nil)
        transfer.cookiesChanged([cookie("user")])
        coordinator().cookiesChanged([cookie("user")])
        precondition(TransferProtocol.requests.count == 1)

        defaults.removePersistentDomain(forName: suite)
        TransferProtocol.requests = []
        TransferProtocol.handler = { _, count in count < 3 ? (503, Data()) : (200, response()) }
        let retry = coordinator()
        retry.cookiesChanged([cookie("user")]); try await settle(retry)
        guard case .succeeded = retry.state else { preconditionFailure("Retry failed") }
        precondition(TransferProtocol.requests.count == 3)

        for failure in [(401, Data()), (200, response(UUID().uuidString)), (200, response(count: 0)), (200, Data("{\"ok\":true}".utf8))] {
            defaults.removePersistentDomain(forName: suite)
            TransferProtocol.requests = []
            TransferProtocol.handler = { _, _ in failure }
            let rejected = coordinator()
            rejected.cookiesChanged([cookie("user")]); try await settle(rejected)
            guard case .failed = rejected.state else { preconditionFailure("Bad receipt accepted") }
            precondition(TransferProtocol.requests.count == 1)
            precondition(defaults.data(forKey: "AppClipLastTransferReceipt") == nil)
        }
        defaults.removePersistentDomain(forName: suite)
        TransferProtocol.requests = []; TransferProtocol.delay = 0.2
        TransferProtocol.handler = { _, _ in (200, response()) }
        let cancelled = coordinator()
        cancelled.cookiesChanged([cookie("user")])
        try await Task.sleep(nanoseconds: 20_000_000)
        cancelled.stop()
        try await Task.sleep(nanoseconds: 300_000_000)
        precondition(defaults.data(forKey: "AppClipLastTransferReceipt") == nil)
        print("App Clip checks passed: invocation validation, scoped HttpOnly upload, receipt validation, deduplication, retries, and cancellation.")
    }
}
