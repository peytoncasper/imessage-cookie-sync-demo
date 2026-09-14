import UIKit
import WebKit

/// A receiving surface with no browser chrome. Loading and recovery controls
/// disappear once the page is ready. Messages owns dismissal and resizing.
final class MessageWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    var requestExpansion: (() -> Void)?
    var onCookiesChanged: (([HTTPCookie]) -> Void)?
    var isTranscript = false {
        didSet {
            webView.isUserInteractionEnabled = !isTranscript
            expansionTap.isEnabled = isTranscript
            refreshCookies()
        }
    }

    private var destination: URL?
    private var isObservingCookies = false
    private var isVisible = false
    private var cookieReadGeneration = 0
    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        // Capture this card's login, independently of Safari and other cards.
        configuration.websiteDataStore = .nonPersistent()
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.allowsBackForwardNavigationGestures = true
        return browser
    }()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let recovery = UIStackView()
    private lazy var expansionTap = UITapGestureRecognizer(target: self, action: #selector(expand))

    deinit {
        if isObservingCookies {
            webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        refreshCookies()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isVisible = false
        cookieReadGeneration += 1
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.adjustsFontForContentSizeCategory = true
        retryButton.setTitle("Try Again", for: .normal)
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
        recovery.axis = .vertical
        recovery.spacing = 12
        recovery.addArrangedSubview(errorLabel)
        recovery.addArrangedSubview(retryButton)
        recovery.translatesAutoresizingMaskIntoConstraints = false
        recovery.isHidden = true
        view.addSubview(recovery)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            recovery.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            recovery.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            recovery.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
        expansionTap.isEnabled = isTranscript
        view.addGestureRecognizer(expansionTap)
    }

    func open(_ invocationURL: URL, baseURL: URL) {
        loadViewIfNeeded()
        guard let target = WebViewMessageLink.target(from: invocationURL, baseURL: baseURL) else {
            destination = nil
            showError("This login card is invalid. Ask for a new card.")
            return
        }
        openTarget(target)
    }

    /// Opens a destination after the caller validates the signed card.
    func openTarget(_ target: URL) {
        loadViewIfNeeded()
        guard WebViewMessageLink.allowsNavigation(to: target) else {
            destination = nil
            showError("This demo can open Hacker News pages only.")
            return
        }
        destination = target
        if !isObservingCookies {
            webView.configuration.websiteDataStore.httpCookieStore.add(self)
            isObservingCookies = true
        }
        retry()
    }

    func stopCapture() {
        cookieReadGeneration += 1
        onCookiesChanged = nil
        if isObservingCookies {
            webView.configuration.websiteDataStore.httpCookieStore.remove(self)
            isObservingCookies = false
        }
        webView.stopLoading()
    }

    func refreshCookies() {
        cookieReadGeneration += 1
        let generation = cookieReadGeneration
        guard isVisible, !isTranscript, destination != nil else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, self.cookieReadGeneration == generation,
                      self.isVisible, !self.isTranscript, self.destination != nil else { return }
                self.onCookiesChanged?(cookies)
            }
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        refreshCookies()
    }

    @objc private func expand() { requestExpansion?() }

    @objc private func retry() {
        guard let destination else { return }
        recovery.isHidden = true
        webView.isHidden = false
        spinner.startAnimating()
        webView.load(URLRequest(url: destination, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20))
    }

    private func showError(_ message: String) {
        spinner.stopAnimating()
        webView.isHidden = true
        errorLabel.text = message
        retryButton.isHidden = destination == nil
        recovery.isHidden = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, WebViewMessageLink.allowsNavigation(to: url) else {
            decisionHandler(.cancel)
            if action.targetFrame?.isMainFrame != false {
                showError("This demo can open Hacker News pages only.")
            }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil, let url = action.request.url,
           WebViewMessageLink.allowsNavigation(to: url) {
            webView.load(action.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        recovery.isHidden = true
        webView.isHidden = false
        spinner.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimating()
        refreshCookies()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    private func handleLoadFailure(_ error: Error) {
        let error = error as NSError
        guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) else { return }
        showError("The page couldn’t load. Check your connection and try again.")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showError("The page stopped responding. Try loading it again.")
    }
}
