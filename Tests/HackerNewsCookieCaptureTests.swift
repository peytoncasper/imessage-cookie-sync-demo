import Foundation

@main
enum HackerNewsCookieCaptureTests {
    static func main() {
        func cookie(domain: String = "news.ycombinator.com", name: String = "user",
                    value: String = "synthetic-test-session", expired: Bool = false) -> HTTPCookie {
            HTTPCookie(properties: [
                .domain: domain, .path: "/", .name: name, .value: value,
                .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE",
                .expires: expired ? Date(timeIntervalSince1970: 1) : Date.distantFuture
            ])!
        }
        var checks = 0
        func check(_ result: Bool) { precondition(result); checks += 1 }
        let auth = cookie()
        let preferences = cookie(name: "preferences")
        check(HackerNewsCookieCapture.isEligible(auth))
        check(HackerNewsCookieCapture.isEligible(cookie(domain: ".ycombinator.com")))
        check(HackerNewsCookieCapture.isEligible(cookie(domain: ".NEWS.YCOMBINATOR.COM")))
        for domain in ["example.com", "news.ycombinator.com.evil.example", "other.ycombinator.com", "evilnews.ycombinator.com"] {
            check(!HackerNewsCookieCapture.isEligible(cookie(domain: domain)))
            check(HackerNewsCookieCapture.fingerprint(in: [cookie(domain: domain)]) == nil)
        }
        check(!HackerNewsCookieCapture.isEligible(cookie(expired: true)))
        check(HackerNewsCookieCapture.fingerprint(in: [cookie(expired: true)]) == nil)
        check(HackerNewsCookieCapture.fingerprint(in: [preferences]) == nil)
        check(HackerNewsCookieCapture.fingerprint(in: [cookie(value: "")]) == nil)
        check(HackerNewsCookieCapture.fingerprint(in: [cookie(name: "User")]) == nil)
        check(HackerNewsCookieCapture.fingerprint(in: []) == nil)
        let fingerprint = HackerNewsCookieCapture.fingerprint(in: [auth])!
        check(fingerprint.count == 64)
        check(fingerprint == HackerNewsCookieCapture.fingerprint(in: [preferences, auth]))
        check(fingerprint != HackerNewsCookieCapture.fingerprint(in: [cookie(value: "different-test-session")]))
        check(HackerNewsCookieCapture.authenticationCookie(in: [auth])?.value == auth.value)
        let automatic = HackerNewsCookieCapture.deduplicationKey(fingerprint: fingerprint, sessionID: nil)
        let completed = HackerNewsCookieCapture.deduplicationKey(fingerprint: fingerprint, sessionID: "session-one")
        check(automatic != completed)
        check(completed == HackerNewsCookieCapture.deduplicationKey(fingerprint: fingerprint, sessionID: "session-one"))
        check(completed != HackerNewsCookieCapture.deduplicationKey(fingerprint: fingerprint, sessionID: "session-two"))
        print("Hacker News cookie capture: \(checks) checks passed.")
    }
}
