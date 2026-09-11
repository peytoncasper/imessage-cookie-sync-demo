import Foundation

/// A card authorizes one short-lived transfer. Permanent backend credentials
/// are never shipped in the App Clip. The server verifies the token signature.
struct AppClipInvocation: Equatable {
    let target: URL
    let sessionID: String
    let token: String
    let expiresAt: Date

    static func parse(_ url: URL, baseURL: URL, now: Date = Date(),
                      clipBundleID: String = Bundle.main.object(forInfoDictionaryKey: "CookieClipBundleIdentifier") as? String
                        ?? "com.example.CookieClipDemo.Clip") -> AppClipInvocation? {
        guard url.absoluteString.utf8.count <= 2048,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.fragment == nil else { return nil }

        let items = components.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count else { return nil }
        let isAppleLink = components.host?.lowercased() == "appclip.apple.com"
        if isAppleLink {
            guard components.path == "/id",
                  items.first(where: { $0.name == "p" })?.value == clipBundleID else { return nil }
        } else {
            guard components.host?.lowercased() == baseURL.host?.lowercased(),
                  components.path == "/open" else { return nil }
        }
        let allowedKeys = ["target", "bbSession", "bbToken", "test", "view"] + (isAppleLink ? ["p"] : [])
        guard items.allSatisfy({ allowedKeys.contains($0.name) }),
              items.first(where: { $0.name == "view" }).map({ $0.value == "web" }) ?? true,
              let rawTarget = items.first(where: { $0.name == "target" })?.value,
              let target = URL(string: rawTarget), WebViewMessageLink.allowsNavigation(to: target),
              let sessionID = items.first(where: { $0.name == "bbSession" })?.value,
              UUID(uuidString: sessionID) != nil,
              let token = items.first(where: { $0.name == "bbToken" })?.value,
              token.range(of: "^ct1\\.[A-Za-z0-9_-]{40,1024}\\.[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }

        let encoded = String(token.split(separator: ".")[1])
        let base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONDecoder().decode(Claims.self, from: data),
              claims.s == sessionID, claims.e - claims.i == 600_000,
              claims.i <= now.timeIntervalSince1970 * 1000 + 5000,
              claims.e > now.timeIntervalSince1970 * 1000 else { return nil }
        return AppClipInvocation(target: target, sessionID: sessionID, token: token,
                                 expiresAt: Date(timeIntervalSince1970: claims.e / 1000))
    }

    private struct Claims: Decodable {
        let s: String
        let i: Double
        let e: Double
    }
}
