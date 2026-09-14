import Foundation

/// URL validation and presentation for iMessage webpage cards.
enum WebViewMessageLink {
    static func prefersCompactPresentation(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .contains(where: { $0.name == "presentation" && $0.value == "compact" }) == true
    }

    static func isWebViewMessage(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .contains(where: { $0.name == "view" && $0.value == "web" }) == true
    }

    static func target(from url: URL, baseURL: URL) -> URL? {
        guard url.absoluteString.utf8.count <= 2048,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == baseURL.host?.lowercased(),
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.fragment == nil,
              components.path == "/open" else { return nil }

        let items = components.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count,
              items.allSatisfy({ ["view", "target", "test", "presentation"].contains($0.name) }),
              items.first(where: { $0.name == "presentation" }).map({ $0.value == "compact" }) ?? true,
              items.first(where: { $0.name == "view" })?.value == "web",
              let value = items.first(where: { $0.name == "target" })?.value,
              let target = URL(string: value),
              allowsNavigation(to: target) else { return nil }
        return target
    }

    static func allowsNavigation(to url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https"
            && components.host?.lowercased() == "news.ycombinator.com"
            && components.user == nil && components.password == nil
            && (components.port == nil || components.port == 443)
    }
}
