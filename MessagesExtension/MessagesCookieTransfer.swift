import Foundation
import OSLog

struct PreparedTransfer {
    let sessionId: String
    let token: String
    let inspectorURL: URL?
}

enum CookieTransferError: LocalizedError {
    case invalidResponse, missingConfiguration, http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The transfer server returned an invalid response."
        case .missingConfiguration: return "Copy a fresh sign-in card URL from your backend, then tap Add Card."
        case .http(let status): return "Session transfer failed (HTTP \(status))."
        }
    }

    var retryable: Bool {
        if case .http(let status) = self { return status == 408 || status == 429 || status >= 500 }
        return false
    }
}

/// Owns one card's transfer lifetime, independently of its presentation.
@MainActor
final class MessagesCookieTransfer {
    enum State: Equatable {
        case idle, sending, retrying
        case succeeded(sessionID: String, count: Int?)
        case failed(String)
    }

    private(set) var state: State = .idle {
        didSet { onStateChanged?(state) }
    }
    var onStateChanged: ((State) -> Void)?
    private let baseURL: URL
    private let clientSecret: String?
    private let session: URLSession
    private let defaults: UserDefaults
    private let retryDelay: UInt64
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var fingerprint: String?
    private var needsCookieRead = true
    private var preparation: PreparedTransfer?
    private var suppliedPreparation: PreparedTransfer?
    private var enabled = false
    private let completedKey = "LastTransferredHNAuthFingerprint"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CookieClipDemo", category: "CookieTransfer")

    init(baseURL: URL, clientSecret: String?, session: URLSession? = nil,
         defaults: UserDefaults = .standard, retryDelay: UInt64 = 5_000_000_000) {
        self.baseURL = baseURL
        self.clientSecret = clientSecret
        self.defaults = defaults
        self.retryDelay = retryDelay
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        }
    }

    deinit { task?.cancel() }

    func reset(preparation: PreparedTransfer? = nil) {
        cancel()
        fingerprint = nil
        needsCookieRead = true
        suppliedPreparation = preparation
        self.preparation = preparation
        state = .idle
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if !enabled {
            cancel()
            // A fresh cookie read resumes a cancelled transfer on activation.
            needsCookieRead = true
            state = .idle
        }
    }

    private func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
    }

    func cookiesChanged(_ cookies: [HTTPCookie]) {
        guard enabled else { return }
        let eligible = cookies.filter { HackerNewsCookieCapture.isEligible($0) }
        let current = HackerNewsCookieCapture.fingerprint(in: eligible)
        guard current != fingerprint || needsCookieRead else { return }
        needsCookieRead = false
        let previous = fingerprint
        cancel()
        fingerprint = current
        if previous != nil, previous != current { preparation = suppliedPreparation }
        guard let current else { state = .idle; return }

        let key = HackerNewsCookieCapture.deduplicationKey(fingerprint: current, sessionID: preparation?.sessionId)
        if defaults.string(forKey: completedKey) == key, let preparation {
            state = .succeeded(sessionID: preparation.sessionId, count: nil)
            return
        }

        state = .sending
        let generation = generation
        task = Task { [weak self] in
            guard let self else { return }
            for attempt in 1...3 {
                do {
                    try Task.checkCancellation()
                    let prepared: PreparedTransfer
                    if let preparation = self.preparation { prepared = preparation }
                    else { prepared = try await self.prepare() }
                    try Task.checkCancellation()
                    guard self.generation == generation else { return }
                    self.preparation = prepared
                    let count = try await self.upload(eligible, preparation: prepared)
                    try Task.checkCancellation()
                    guard self.generation == generation else { return }
                    self.defaults.set(HackerNewsCookieCapture.deduplicationKey(fingerprint: current, sessionID: prepared.sessionId),
                                      forKey: self.completedKey)
                    self.state = .succeeded(sessionID: prepared.sessionId, count: count)
                    self.logger.notice("[CookieClipTransfer] Transfer succeeded: \(count) cookies; session \(prepared.sessionId, privacy: .public)")
                    return
                } catch {
                    guard !Task.isCancelled, self.generation == generation else { return }
                    let retryable = (error as? CookieTransferError)?.retryable ?? (error is URLError)
                    guard retryable, attempt < 3 else {
                        self.state = .failed(error.localizedDescription)
                        self.logger.error("[CookieClipTransfer] Transfer failed on attempt \(attempt)")
                        return
                    }
                    self.state = .retrying
                    do { try await Task.sleep(nanoseconds: self.retryDelay * UInt64(attempt)) }
                    catch { return }
                    self.state = .sending
                }
            }
        }
    }

    func prepare() async throws -> PreparedTransfer {
        guard let clientSecret, clientSecret.count >= 32 else { throw CookieTransferError.missingConfiguration }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/transfers/prepare"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        let data = try await send(request)
        guard let result = try? JSONDecoder().decode(PreparationResponse.self, from: data), result.ok,
              !result.sessionId.isEmpty, !result.token.isEmpty else { throw CookieTransferError.invalidResponse }
        return PreparedTransfer(sessionId: result.sessionId, token: result.token,
                                inspectorURL: result.inspectorUrl.flatMap(URL.init(string:)))
    }

    private func upload(_ cookies: [HTTPCookie], preparation: PreparedTransfer) async throws -> Int {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/cookies"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(preparation.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Payload(sessionId: preparation.sessionId, cookies: cookies.map(Cookie.init)))
        let data = try await send(request)
        guard let result = try? JSONDecoder().decode(UploadResponse.self, from: data), result.ok,
              result.sessionId == preparation.sessionId,
              result.injected > 0, result.injected <= cookies.count else { throw CookieTransferError.invalidResponse }
        return result.injected
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw CookieTransferError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw CookieTransferError.http(response.statusCode) }
        return data
    }

    private struct PreparationResponse: Decodable {
        let ok: Bool
        let sessionId: String
        let token: String
        let inspectorUrl: String?
    }
    private struct UploadResponse: Decodable {
        let ok: Bool
        let sessionId: String
        let injected: Int
    }
    private struct Payload: Encodable {
        let sessionId: String
        let cookies: [Cookie]
    }
    private struct Cookie: Encodable {
        let name: String
        let value: String
        let url: String?
        let domain: String?
        let path: String
        let secure: Bool
        let httpOnly: Bool
        let expires: Double?

        init(_ cookie: HTTPCookie) {
            name = cookie.name
            value = cookie.value
            path = cookie.path.isEmpty ? "/" : cookie.path
            let host = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            url = name.hasPrefix("__Host-") ? "https://\(host)\(path)" : nil
            domain = url == nil ? cookie.domain : nil
            secure = cookie.isSecure
            httpOnly = cookie.isHTTPOnly
            expires = cookie.expiresDate?.timeIntervalSince1970
        }
    }
    private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
