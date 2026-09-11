import Foundation
import WebKit

struct CookiePreview: Identifiable {
    let id = UUID()
    let name: String
    let domain: String
    let prefix: String
    let valueLength: Int
    let isHTTPOnly: Bool
    let isSecure: Bool
}

@MainActor
final class BrowserModel: NSObject, ObservableObject {
    @Published var address = "https://example.com"
    @Published var status = "Ready"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var cookiePreviews: [CookiePreview] = []
    @Published var isShowingCookies = false
    @Published var validationMessage: String?

    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()

        // Keep this proof of concept isolated from Safari and erase its state
        // when the App Clip is removed from memory.
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = nil
    }

    func loadAddress() {
        guard let url = normalizedHTTPSURL(from: address) else {
            validationMessage = "Enter a valid HTTPS URL."
            return
        }

        validationMessage = nil
        address = url.absoluteString
        status = "Loading…"
        webView.load(URLRequest(url: url))
    }

    func applyInvocationURL(_ invocationURL: URL) {
        guard let components = URLComponents(url: invocationURL, resolvingAgainstBaseURL: false) else {
            return
        }

        if let target = components.queryItems?.first(where: { $0.name == "target" })?.value,
           let targetURL = normalizedHTTPSURL(from: target) {
            address = targetURL.absoluteString
            loadAddress()
            return
        }

        guard let handoffID = components.queryItems?.first(where: { $0.name == "h" })?.value,
              !handoffID.isEmpty else {
            return
        }

        status = "Opening secure link…"
        Task { await redeemHandoff(handoffID, from: invocationURL) }
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func captureCookiePrefixes() {
        guard let pageURL = webView.url, let host = pageURL.host?.lowercased() else {
            validationMessage = "Load a webpage before inspecting its cookie store."
            return
        }

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self else { return }

                let matchingCookies = cookies
                    .filter { Self.cookie($0, matchesHost: host) }
                    .sorted {
                        if $0.domain == $1.domain { return $0.name < $1.name }
                        return $0.domain < $1.domain
                    }

                self.cookiePreviews = matchingCookies.map { cookie in
                    let prefix = String(cookie.value.prefix(8))

                    #if DEBUG
                    print("[CookieClipDemo] \(cookie.domain) \(cookie.name)=\(prefix)…")
                    #endif

                    return CookiePreview(
                        name: cookie.name,
                        domain: cookie.domain,
                        prefix: prefix,
                        valueLength: cookie.value.count,
                        isHTTPOnly: cookie.isHTTPOnly,
                        isSecure: cookie.isSecure
                    )
                }

                self.validationMessage = nil
                self.isShowingCookies = true
            }
        }
    }

    private func normalizedHTTPSURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard let url = URL(string: candidate),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }

        return url
    }

    private func redeemHandoff(_ handoffID: String, from invocationURL: URL) async {
        guard var components = URLComponents(url: invocationURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host != nil else {
            validationMessage = "The secure link is invalid."
            status = "Ready"
            return
        }

        components.path = "/api/handoffs/redeem"
        components.query = nil
        components.fragment = nil
        guard let endpoint = components.url else {
            validationMessage = "The secure link is invalid."
            status = "Ready"
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(HandoffRequest(id: handoffID))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                validationMessage = "This secure link is invalid, expired, or already used."
                status = "Ready"
                return
            }

            let result = try JSONDecoder().decode(HandoffResponse.self, from: data)
            guard let targetURL = normalizedHTTPSURL(from: result.targetUrl) else {
                validationMessage = "The secure link returned an invalid destination."
                status = "Ready"
                return
            }

            address = targetURL.absoluteString
            loadAddress()
        } catch {
            validationMessage = "Unable to open the secure link. Try again."
            status = "Ready"
        }
    }

    private static func cookie(_ cookie: HTTPCookie, matchesHost host: String) -> Bool {
        let domain = cookie.domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return host == domain || host.hasSuffix(".\(domain)")
    }

    private func updateNavigationState() {
        address = webView.url?.absoluteString ?? address
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

private struct HandoffRequest: Encodable {
    let id: String
}

private struct HandoffResponse: Decodable {
    let targetUrl: String
}

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        status = "Loading…"
        updateNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        status = webView.title ?? "Loaded"
        updateNavigationState()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        status = "Load failed"
        validationMessage = error.localizedDescription
        updateNavigationState()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        status = "Load failed"
        validationMessage = error.localizedDescription
        updateNavigationState()
    }
}

extension BrowserModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Keep target=_blank and window.open login steps inside this App Clip's
        // single isolated WebView so the cookie store remains consistent.
        if navigationAction.targetFrame == nil, let requestURL = navigationAction.request.url {
            webView.load(URLRequest(url: requestURL))
        }
        return nil
    }
}
