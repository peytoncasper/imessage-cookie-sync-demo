import Foundation

@main
enum SignInCardTests {
    static func main() throws {
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
        let invocation = SignInCard.parse(url, baseURL: base)!
        precondition(invocation.sessionID == sid)
        precondition(SignInCard.parse(url, baseURL: base, now: now.addingTimeInterval(601)) == nil)
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
        ] { precondition(SignInCard.parse(URL(string: bad)!, baseURL: base) == nil) }
        var apple = card
        apple.host = "appclip.apple.com"; apple.path = "/id"
        apple.queryItems?.append(.init(name: "p", value: "com.example.CookieClipDemo.Clip"))
        precondition(SignInCard.parse(apple.url!, baseURL: base) == nil)
        card.queryItems?.removeAll(where: { $0.name == "bbToken" })
        precondition(SignInCard.parse(card.url!, baseURL: base) == nil)

        print("Sign-in card checks passed: origin, destination, claims, expiration, and rejected App Clip links.")
    }
}
