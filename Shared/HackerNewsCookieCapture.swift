import Foundation
import CryptoKit

enum HackerNewsCookieCapture {
    static func isEligible(_ cookie: HTTPCookie, now: Date = Date()) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return (domain == "news.ycombinator.com" || domain == "ycombinator.com")
            && (cookie.expiresDate.map { $0 > now } ?? true)
    }

    static func authenticationCookie(in cookies: [HTTPCookie]) -> HTTPCookie? {
        cookies.first { isEligible($0) && $0.name == "user" && !$0.value.isEmpty }
    }

    static func fingerprint(in cookies: [HTTPCookie]) -> String? {
        guard let cookie = authenticationCookie(in: cookies) else { return nil }
        let input = Data("\(cookie.domain)|\(cookie.name)|\(cookie.value)".utf8)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    static func deduplicationKey(fingerprint: String, sessionID: String?) -> String {
        "\(fingerprint)|\(sessionID ?? "automatic")"
    }
}
