import Foundation
import CryptoKit
import OSLog

struct AppClipTransferReceipt: Codable, Equatable {
    let grantID: String
    let sessionID: String
    let injected: Int
    let requestID: String
    let completedAt: Date
}

@MainActor
final class AppClipCookieTransfer {
    enum State: Equatable {
        case idle, sending
        case succeeded(AppClipTransferReceipt)
        case failed(String)
    }

    private(set) var state: State = .idle {
        didSet { onStateChanged?(state) }
    }
    var onStateChanged: ((State) -> Void)?
    private let invocation: AppClipInvocation
    private let endpoint: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private let retryDelay: UInt64
    private let grantID: String
    private var task: Task<Void, Never>?
    private var fingerprint: String?
    private var generation = UUID()
    private var consumed = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CookieClipDemo.Clip", category: "CookieTransfer")

    init(invocation: AppClipInvocation, baseURL: URL, session: URLSession? = nil,
         defaults: UserDefaults = .standard, retryDelay: UInt64 = 3_000_000_000) {
        self.invocation = invocation
        self.endpoint = baseURL.appendingPathComponent("api/cookies")
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        }
        self.defaults = defaults
        self.retryDelay = retryDelay
        self.grantID = SHA256.hash(data: Data(invocation.token.utf8)).map { String(format: "%02x", $0) }.joined()
        if let data = defaults.data(forKey: "AppClipLastTransferReceipt"),
           let receipt = try? JSONDecoder().decode(AppClipTransferReceipt.self, from: data),
           receipt.sessionID == invocation.sessionID, receipt.grantID == grantID {
            consumed = true
            state = .succeeded(receipt)
        }
    }

    deinit { task?.cancel() }

    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
    }

    func cookiesChanged(_ cookies: [HTTPCookie]) {
        let eligible = cookies.filter { HackerNewsCookieCapture.isEligible($0) }
        let current = HackerNewsCookieCapture.fingerprint(in: eligible)
        guard current != fingerprint else { return }
        stop()
        fingerprint = current
        guard !consumed else { return }
        guard current != nil else { state = .idle; return }
        guard invocation.expiresAt > Date() else {
            fail("This sign-in card expired. Open a fresh card to connect your session.")
            return
        }

        state = .sending
        recordDiagnostic("transferring")
        let generation = generation
        let payload = Payload(sessionId: invocation.sessionID, cookies: eligible.map(Cookie.init))
        task = Task { [weak self] in
            guard let self else { return }
            for attempt in 1...3 {
                do {
                    try Task.checkCancellation()
                    guard self.invocation.expiresAt > Date() else { throw TransferError.expired }
                    var request = URLRequest(url: self.endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 20
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(self.invocation.token)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONEncoder().encode(payload)
                    let (data, response) = try await self.session.data(for: request)
                    try Task.checkCancellation()
                    guard self.generation == generation else { return }
                    guard let response = response as? HTTPURLResponse else { throw TransferError.invalidResponse }
                    guard (200...299).contains(response.statusCode) else {
                        throw TransferError.http(response.statusCode)
                    }
                    guard let result = try? JSONDecoder().decode(Response.self, from: data), result.ok,
                          result.sessionId == self.invocation.sessionID,
                          result.injected > 0, result.injected <= payload.cookies.count else {
                        throw TransferError.invalidResponse
                    }
                    let receipt = AppClipTransferReceipt(grantID: self.grantID, sessionID: result.sessionId, injected: result.injected,
                                                         requestID: result.requestId, completedAt: Date())
                    self.defaults.set(try JSONEncoder().encode(receipt), forKey: "AppClipLastTransferReceipt")
                    self.consumed = true
                    self.state = .succeeded(receipt)
                    self.recordDiagnostic("transferred")
                    self.logger.notice("App Clip transferred \(result.injected) cookies; session \(result.sessionId, privacy: .public)")
                    return
                } catch {
                    guard !Task.isCancelled, self.generation == generation else { return }
                    let retryable = (error as? TransferError)?.retryable ?? (error is URLError)
                    if retryable && attempt < 3 {
                        do { try await Task.sleep(nanoseconds: self.retryDelay * UInt64(attempt)) }
                        catch { return }
                    } else {
                        self.fail((error as? TransferError)?.message ?? "Your session couldn't connect. Open a fresh sign-in card to try again.")
                        return
                    }
                }
            }
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        recordDiagnostic("transfer_failed")
        logger.error("App Clip transfer did not complete")
    }

    private func recordDiagnostic(_ stage: String) {
        defaults.set(["stage": stage, "date": Date(), "sessionID": invocation.sessionID],
                     forKey: "AppClipDiagnostic")
    }

    private struct Payload: Encodable {
        let sessionId: String
        let cookies: [Cookie]
    }

    private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    private struct Cookie: Encodable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let secure: Bool
        let httpOnly: Bool
        let expires: Double?

        init(_ cookie: HTTPCookie) {
            name = cookie.name; value = cookie.value; domain = cookie.domain
            path = cookie.path.isEmpty ? "/" : cookie.path
            secure = cookie.isSecure; httpOnly = cookie.isHTTPOnly
            expires = cookie.expiresDate?.timeIntervalSince1970
        }
    }
    private struct Response: Decodable {
        let ok: Bool
        let sessionId: String
        let requestId: String
        let injected: Int
    }
    private enum TransferError: Error {
        case invalidResponse, expired, http(Int)
        var retryable: Bool {
            if case .http(let code) = self { return code == 408 || code == 429 || code >= 500 }
            return false
        }
        var message: String {
            switch self {
            case .expired, .http(401), .http(404), .http(409):
                return "This sign-in card expired or was already used. Open a fresh card to connect your session."
            default:
                return "Your session couldn't connect. Open a fresh sign-in card to try again."
            }
        }
    }
}
