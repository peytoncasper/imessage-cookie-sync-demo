import SwiftUI
import WebKit

struct CookieInspectorView: View {
    @StateObject private var browser = BrowserModel()
    @FocusState private var addressIsFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                addressBar
                Divider()
                BrowserWebView(browser: browser)
                Divider()
                browserToolbar
            }
            .navigationTitle("Cookie Clip")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "Unable to Continue",
                isPresented: Binding(
                    get: { browser.validationMessage != nil },
                    set: { if !$0 { browser.validationMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(browser.validationMessage ?? "Unknown error")
            }
            .sheet(isPresented: $browser.isShowingCookies) {
                CookieResultsView(cookies: browser.cookiePreviews)
                    .presentationDetents([.medium, .large])
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                browser.applyInvocationURL(url)
            }
            .task {
                if browser.webView.url == nil {
                    browser.loadAddress()
                }
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)

            TextField("https://example.com", text: $browser.address)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($addressIsFocused)
                .onSubmit {
                    browser.loadAddress()
                    addressIsFocused = false
                }

            Button("Go") {
                browser.loadAddress()
                addressIsFocused = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
    }

    private var browserToolbar: some View {
        HStack {
            Button(action: browser.goBack) {
                Image(systemName: "chevron.backward")
            }
            .disabled(!browser.canGoBack)

            Button(action: browser.goForward) {
                Image(systemName: "chevron.forward")
            }
            .disabled(!browser.canGoForward)

            Button(action: browser.reload) {
                Image(systemName: "arrow.clockwise")
            }

            Text(browser.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Button(action: browser.captureCookiePrefixes) {
                Label("Cookies", systemImage: "checkmark.shield")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
    }
}

private struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var browser: BrowserModel

    func makeUIView(context: Context) -> WKWebView {
        browser.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct CookieResultsView: View {
    let cookies: [CookiePreview]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if cookies.isEmpty {
                    ContentUnavailableView(
                        "No Matching Cookies",
                        systemImage: "tray",
                        description: Text(
                            "The current host has no cookies in this WebView. " +
                            "The site may use local storage or another authentication mechanism."
                        )
                    )
                } else {
                    List(cookies) { cookie in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(cookie.name)
                                .font(.headline)
                            Text(cookie.domain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(cookie.prefix)…  (\(cookie.valueLength) characters)")
                                .font(.system(.body, design: .monospaced))
                            Text(attributes(for: cookie))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .textSelection(.disabled)
                    }
                }
            }
            .navigationTitle("Cookie prefixes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Only the first eight characters are shown. Nothing is uploaded or persisted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
        }
    }

    private func attributes(for cookie: CookiePreview) -> String {
        var values: [String] = []
        if cookie.isHTTPOnly { values.append("HttpOnly") }
        if cookie.isSecure { values.append("Secure") }
        return values.isEmpty ? "No HttpOnly/Secure flags" : values.joined(separator: " · ")
    }
}
