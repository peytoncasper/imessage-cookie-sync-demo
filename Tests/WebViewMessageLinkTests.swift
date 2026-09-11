import Foundation

@main
enum WebViewMessageLinkTests {
    static func main() {
        let base = URL(string: "https://cookieclip.example")!
        let target = "https://news.ycombinator.com/login?goto=news"
        func card(_ target: String) -> URL {
            var components = URLComponents(url: base.appendingPathComponent("open"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "view", value: "web"), URLQueryItem(name: "target", value: target)]
            return components.url!
        }
        let valid = card(target)
        precondition(WebViewMessageLink.isWebViewMessage(valid))
        precondition(WebViewMessageLink.target(from: valid, baseURL: base)?.absoluteString == target)

        let rejectedTargets = [
            "http://news.ycombinator.com/login", "https://example.com/login",
            "https://news.ycombinator.com.evil.example/login",
            "https://evil.news.ycombinator.com/login", "https://news.ycombinator.com:444/login",
            "https://user:password@news.ycombinator.com/login", "javascript:alert(1)",
            "file:///etc/passwd", "//news.ycombinator.com/login"
        ]
        for target in rejectedTargets {
            precondition(WebViewMessageLink.target(from: card(target), baseURL: base) == nil)
        }
        for mutation in [
            valid.absoluteString.replacingOccurrences(of: "https://cookieclip", with: "http://cookieclip"),
            valid.absoluteString.replacingOccurrences(of: "cookieclip.example", with: "evil.example"),
            valid.absoluteString.replacingOccurrences(of: "/open?", with: "/other?"),
            valid.absoluteString.replacingOccurrences(of: "https://cookieclip", with: "https://user@cookieclip"),
            valid.absoluteString.replacingOccurrences(of: ".example/open", with: ".example:444/open"),
            valid.absoluteString + "&target=https%3A%2F%2Fexample.com",
            valid.absoluteString + "&view=web", valid.absoluteString + "&bbToken=ct1.fake",
            valid.absoluteString + "#fragment", valid.absoluteString + "&test=" + String(repeating: "x", count: 2048)
        ] {
            precondition(WebViewMessageLink.target(from: URL(string: mutation)!, baseURL: base) == nil)
        }
        precondition(WebViewMessageLink.target(from: URL(string: valid.absoluteString + "&test=linq")!, baseURL: base) != nil)
        precondition(WebViewMessageLink.allowsNavigation(to: URL(string: "https://NEWS.YCOMBINATOR.COM:443/item?id=1")!))
        precondition(!WebViewMessageLink.isWebViewMessage(base))
        let compact = URL(string: valid.absoluteString + "&presentation=compact")!
        precondition(WebViewMessageLink.target(from: compact, baseURL: base) != nil)
        precondition(WebViewMessageLink.prefersCompactPresentation(compact))
        precondition(!WebViewMessageLink.prefersCompactPresentation(valid))
        precondition(WebViewMessageLink.target(from: URL(string: compact.absoluteString + "&presentation=compact")!, baseURL: base) == nil)
        precondition(WebViewMessageLink.target(from: URL(string: valid.absoluteString + "&presentation=unknown")!, baseURL: base) == nil)
        print("WebView message routing: 29 checks passed.")
    }
}
