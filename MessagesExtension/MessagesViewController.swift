import Messages
import UIKit
import WebKit

final class MessagesViewController: MSMessagesAppViewController {
    private let loginURL = URL(string: "https://news.ycombinator.com/login")!
    private let brandColor = UIColor(red: 1, green: 69 / 255, blue: 0, alpha: 1)

    private var invocationBaseURL: URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: "CookieClipBaseURL") as? String
        return URL(string: configured ?? "https://cookieclip.example")!
    }

    private lazy var transfer = MessagesCookieTransfer(
        baseURL: invocationBaseURL,
        clientSecret: Bundle.main.object(forInfoDictionaryKey: "CookieTransferClientSecret") as? String
    )
    private var availableCookies: [HTTPCookie] = []
    private var isActive = false
    private var suppressAutomaticTransfer = false {
        didSet { updateCaptureState() }
    }
    private var transferGeneration = UUID()
    private var cardTask: Task<Void, Never>?
    private var selectedLegacyURL: URL?

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = true
        return view
    }()

    private lazy var transferStatusLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var transferPanel = makeTransferPanel()
    private var webViewTopWithTransferPanel: NSLayoutConstraint?
    private var webViewTopWithoutTransferPanel: NSLayoutConstraint?

    private lazy var backButton = toolbarButton(
        systemName: "chevron.left",
        accessibilityLabel: "Back",
        action: #selector(goBack)
    )

    private lazy var reloadButton = toolbarButton(
        systemName: "arrow.clockwise",
        accessibilityLabel: "Reload",
        action: #selector(reload)
    )

    private lazy var compactView = makeCompactView()
    private lazy var expandedView = makeExpandedView()
    private var messageWebViewController: MessageWebViewController?
    private var selectedWebViewURL: URL?
    private var observedCookieStore: WKHTTPCookieStore?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        transfer.onStateChanged = { [weak self] state in self?.showTransferState(state) }
    }

    deinit {
        cardTask?.cancel()
        observedCookieStore?.remove(self)
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        isActive = true
        updateCaptureState()
        showMessage(conversation.selectedMessage)
    }

    override func willResignActive(with conversation: MSConversation) {
        super.willResignActive(with: conversation)
        isActive = false
        transferGeneration = UUID()
        cardTask?.cancel()
        cardTask = nil
        suppressAutomaticTransfer = false
        updateCaptureState()
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        showMessage(message)
    }

    private func showMessage(_ message: MSMessage?) {
        if openWebViewMessageIfNeeded(message) { return }
        removeMessageWebView()
        observeTransferCookies()
        showCurrentPresentation()
        prewarmLoginIfNeeded()
        openSelectedMessageIfNeeded(message)
        refreshCookies()
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        updateCaptureState()
        messageWebViewController?.isTranscript = presentationStyle == .transcript
        if messageWebViewController == nil { refreshCookies() }
        showCurrentPresentation()
    }

    private func observeTransferCookies() {
        guard observedCookieStore == nil else { return }
        observedCookieStore = webView.configuration.websiteDataStore.httpCookieStore
        observedCookieStore?.add(self)
    }

    private func showCurrentPresentation() {
        if messageWebViewController != nil { return }
        let destination = presentationStyle == .compact ? compactView : expandedView

        for child in view.subviews where child !== destination {
            child.removeFromSuperview()
        }

        guard destination.superview == nil else { return }
        view.addSubview(destination)
        NSLayoutConstraint.activate([
            destination.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            destination.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            destination.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            destination.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        prewarmLoginIfNeeded()
    }

    private func openWebViewMessageIfNeeded(_ message: MSMessage?) -> Bool {
        guard let url = message?.url, WebViewMessageLink.isWebViewMessage(url) else { return false }
        suppressAutomaticTransfer = true
        if observedCookieStore != nil {
            webView.stopLoading()
            observedCookieStore?.remove(self)
            observedCookieStore = nil
        }
        if selectedWebViewURL != url || messageWebViewController == nil {
            removeMessageWebView()
            resetTransferSession()
            suppressAutomaticTransfer = true
            let invocation = AppClipInvocation.parse(url, baseURL: invocationBaseURL)
            if let invocation {
                transfer.reset(preparation: PreparedTransfer(
                    sessionId: invocation.sessionID, token: invocation.token, inspectorURL: nil
                ))
            }
            let controller = MessageWebViewController()
            controller.isTranscript = presentationStyle == .transcript
            controller.requestExpansion = { [weak self] in
                self?.requestPresentationStyle(WebViewMessageLink.prefersCompactPresentation(url) ? .compact : .expanded)
            }
            controller.onCookiesChanged = { [weak self, weak controller] cookies in
                guard let self, let controller, self.messageWebViewController === controller,
                      !self.suppressAutomaticTransfer else { return }
                self.availableCookies = cookies.filter(self.isAllowedCookie)
                self.updateTransferAvailability()
            }
            messageWebViewController = controller
            selectedWebViewURL = url
            for child in view.subviews { child.removeFromSuperview() }
            addChild(controller)
            let browserView = controller.view!
            browserView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(browserView)
            NSLayoutConstraint.activate([
                browserView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                browserView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                browserView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                browserView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
            controller.didMove(toParent: self)
            if let invocation { controller.openTarget(invocation.target) }
            else { controller.open(url, baseURL: invocationBaseURL) }
        }

        // Transcript controllers are also created for cards merely visible in
        // the conversation. Expand only when the user taps, never on rendering.
        messageWebViewController?.isTranscript = presentationStyle == .transcript
        suppressAutomaticTransfer = false
        messageWebViewController?.refreshCookies()
        if presentationStyle == .transcript {
            preferredContentSize = CGSize(width: 320, height: 240)
        }
        if presentationStyle != .transcript {
            let requestedStyle: MSMessagesAppPresentationStyle = WebViewMessageLink.prefersCompactPresentation(url) ? .compact : .expanded
            if presentationStyle != requestedStyle { requestPresentationStyle(requestedStyle) }
        }
        return true
    }

    private func removeMessageWebView() {
        guard let controller = messageWebViewController else { return }
        controller.stopCapture()
        resetTransferSession()
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        messageWebViewController = nil
        selectedWebViewURL = nil
        suppressAutomaticTransfer = false
    }

    private func resetTransferSession() {
        transferGeneration = UUID()
        cardTask?.cancel()
        cardTask = nil
        transfer.reset()
        availableCookies.removeAll()
        selectedLegacyURL = nil
        suppressAutomaticTransfer = false
    }

    private func updateCaptureState() {
        transfer.setEnabled(isActive && !suppressAutomaticTransfer && presentationStyle != .transcript)
    }

    private func makeCompactView() -> UIView {
        let mark = brandMark(size: 38)

        let title = UILabel()
        title.text = "Browserbase"
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true

        let subtitle = UILabel()
        subtitle.text = "Sign in to Hacker News or add a sign-in card"
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = .secondaryLabel
        subtitle.adjustsFontForContentSizeCategory = true

        let labels = UIStackView(arrangedSubviews: [title, subtitle])
        labels.axis = .vertical
        labels.spacing = 2

        let openButton = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Sign In"
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = brandColor
        openButton.configuration = configuration
        openButton.addTarget(self, action: #selector(openLogin), for: .touchUpInside)

        let addCardButton = UIButton(type: .system)
        var addCardConfiguration = UIButton.Configuration.tinted()
        addCardConfiguration.image = UIImage(systemName: "paperplane.fill")
        addCardConfiguration.title = "Add Card"
        addCardConfiguration.imagePadding = 5
        addCardConfiguration.cornerStyle = .capsule
        addCardConfiguration.baseForegroundColor = brandColor
        addCardButton.configuration = addCardConfiguration
        addCardButton.addTarget(self, action: #selector(addLoginLink), for: .touchUpInside)

        let heading = UIStackView(arrangedSubviews: [mark, labels])
        heading.axis = .horizontal
        heading.alignment = .center
        heading.spacing = 12

        let buttons = UIStackView(arrangedSubviews: [addCardButton, openButton])
        buttons.axis = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 10

        let content = UIStackView(arrangedSubviews: [heading, buttons])
        content.axis = .vertical
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            content.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func makeExpandedView() -> UIView {
        let title = UILabel()
        title.text = "news.ycombinator.com"
        title.font = .preferredFont(forTextStyle: .subheadline)
        title.textAlignment = .center
        title.adjustsFontForContentSizeCategory = true

        let doneButton = UIButton(type: .system)
        doneButton.setTitle("Done", for: .normal)
        doneButton.addTarget(self, action: #selector(closeLogin), for: .touchUpInside)

        let toolbar = UIStackView(arrangedSubviews: [backButton, reloadButton, title, doneButton])
        toolbar.axis = .horizontal
        toolbar.alignment = .center
        toolbar.spacing = 12
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbar)
        container.addSubview(separator)
        container.addSubview(transferPanel)
        container.addSubview(webView)

        let topWithPanel = webView.topAnchor.constraint(equalTo: transferPanel.bottomAnchor, constant: 8)
        let topWithoutPanel = webView.topAnchor.constraint(equalTo: separator.bottomAnchor)
        webViewTopWithTransferPanel = topWithPanel
        webViewTopWithoutTransferPanel = topWithoutPanel

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            toolbar.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            toolbar.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),

            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            transferPanel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            transferPanel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            transferPanel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),

            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        setTransferPanelVisible(hasAuthenticationCookie)
        return container
    }

    private func makeTransferPanel() -> UIView {
        let brandTitle = UILabel()
        brandTitle.text = "Hacker News sign-in detected"
        brandTitle.font = .preferredFont(forTextStyle: .subheadline)
        brandTitle.adjustsFontForContentSizeCategory = true

        let brandHeading = UIStackView(arrangedSubviews: [brandMark(size: 24), brandTitle])
        brandHeading.axis = .horizontal
        brandHeading.alignment = .center
        brandHeading.spacing = 8

        let transferContent = UIStackView(arrangedSubviews: [brandHeading, transferStatusLabel])
        transferContent.axis = .vertical
        transferContent.spacing = 8
        transferContent.translatesAutoresizingMaskIntoConstraints = false

        let panel = UIView()
        panel.backgroundColor = .secondarySystemBackground
        panel.layer.cornerRadius = 12
        panel.layer.cornerCurve = .continuous
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(transferContent)
        NSLayoutConstraint.activate([
            transferContent.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            transferContent.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            transferContent.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            transferContent.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10)
        ])
        return panel
    }

    private func brandMark(size: CGFloat) -> UIImageView {
        let mark = UIImageView(image: BrowserbaseLogo.image(size: size))
        mark.contentMode = .scaleAspectFit
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.accessibilityLabel = "Browserbase"
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: size),
            mark.heightAnchor.constraint(equalToConstant: size)
        ])
        return mark
    }

    private func toolbarButton(
        systemName: String,
        accessibilityLabel: String,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func openLogin() {
        requestPresentationStyle(.expanded)
    }

    @objc private func addLoginLink() {
        guard let conversation = activeConversation, cardTask == nil else { return }
        let generation = transferGeneration
        cardTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.transferGeneration == generation {
                    self.cardTask = nil
                    self.suppressAutomaticTransfer = false
                    self.refreshCookies()
                }
            }
            do {
                self.suppressAutomaticTransfer = true
                let preparation: PreparedTransfer
                let link: URL
                let pastedURL = UIPasteboard.general.url
                    ?? UIPasteboard.general.string.flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                if let pastedURL, let invocation = AppClipInvocation.parse(pastedURL, baseURL: self.invocationBaseURL) {
                    preparation = PreparedTransfer(sessionId: invocation.sessionID, token: invocation.token, inspectorURL: nil)
                    // Normalize App Clip URLs and older cards into the Messages webpage route.
                    guard var components = URLComponents(url: self.invocationBaseURL, resolvingAgainstBaseURL: false) else {
                        throw CookieTransferError.invalidResponse
                    }
                    components.path = "/open"
                    components.queryItems = [
                        .init(name: "view", value: "web"), .init(name: "target", value: invocation.target.absoluteString),
                        .init(name: "bbSession", value: invocation.sessionID), .init(name: "bbToken", value: invocation.token)
                    ]
                    guard let url = components.url else { throw CookieTransferError.invalidResponse }
                    link = url
                } else {
                    preparation = try await self.transfer.prepare()
                    guard let url = self.invocationURL(for: self.loginURL, preparation: preparation) else {
                        throw CookieTransferError.invalidResponse
                    }
                    link = url
                }
                try Task.checkCancellation()
                guard self.transferGeneration == generation else { return }

                let layout = MSMessageTemplateLayout()
                layout.image = BrowserbaseLogo.image(size: 200)
                layout.imageTitle = "Browserbase Cookie Clip"
                layout.imageSubtitle = "Recorded Hacker News login"
                layout.caption = "Open the login experience"
                layout.subcaption = "Cookies transfer automatically after sign-in"
                layout.trailingSubcaption = "Session ready"

                let message = MSMessage(session: MSSession())
                message.layout = layout
                message.url = link
                message.summaryText = "Open the Browserbase Cookie Clip demo"

                try await conversation.insert(message)
                try Task.checkCancellation()
                guard self.isActive, self.transferGeneration == generation else { return }
                self.presentPreparedSession(preparation)
            } catch {
                guard !Task.isCancelled, self.transferGeneration == generation else { return }
                self.presentInsertionError(error)
            }
        }
    }

    @objc private func closeLogin() {
        requestPresentationStyle(.compact)
    }

    @objc private func goBack() {
        webView.goBack()
    }

    @objc private func reload() {
        webView.reload()
    }

    private func prewarmLoginIfNeeded() {
        guard webView.url == nil, !webView.isLoading else { return }

        var request = URLRequest(url: loginURL)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 10
        webView.load(request)
    }

    private func invocationURL(for targetURL: URL, preparation: PreparedTransfer? = nil) -> URL? {
        var components = URLComponents(url: invocationBaseURL, resolvingAgainstBaseURL: false)
        components?.path = "/open"
        var queryItems = [URLQueryItem(name: "target", value: targetURL.absoluteString)]
        if let preparation {
            queryItems.append(URLQueryItem(name: "bbSession", value: preparation.sessionId))
            queryItems.append(URLQueryItem(name: "bbToken", value: preparation.token))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    private func openSelectedMessageIfNeeded(_ message: MSMessage?) {
        guard let messageURL = message?.url,
              let components = URLComponents(url: messageURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == invocationBaseURL.host?.lowercased(),
              components.path == "/open",
              let target = components.queryItems?.first(where: { $0.name == "target" })?.value,
              let targetURL = URL(string: target),
              WebViewMessageLink.allowsNavigation(to: targetURL) else {
            return
        }

        let sessionId = components.queryItems?.first(where: { $0.name == "bbSession" })?.value
        let token = components.queryItems?.first(where: { $0.name == "bbToken" })?.value
        let hasPreparedTransfer = sessionId?.range(
            of: "^[A-Za-z0-9_-]{1,128}$",
            options: .regularExpression
        ) != nil && token?.hasPrefix("ct1.") == true

        guard selectedLegacyURL != messageURL else { return }
        resetTransferSession()
        if presentationStyle != .transcript { requestPresentationStyle(.expanded) }
        if hasPreparedTransfer, let sessionId, let token {
            transfer.reset(preparation: PreparedTransfer(sessionId: sessionId, token: token, inspectorURL: nil))
            suppressAutomaticTransfer = true
            let generation = transferGeneration
            cardTask = Task { [weak self] in
                guard let self else { return }
                await self.clearHackerNewsCookies()
                guard !Task.isCancelled, self.transferGeneration == generation else { return }
                self.cardTask = nil
                self.suppressAutomaticTransfer = false
                self.selectedLegacyURL = messageURL
                self.load(targetURL)
            }
        } else {
            selectedLegacyURL = messageURL
            load(targetURL)
        }
    }

    private func load(_ targetURL: URL) {
        var request = URLRequest(url: targetURL)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 10
        webView.load(request)
    }

    private func clearHackerNewsCookies() async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }

        for cookie in cookies where isAllowedCookie(cookie) {
            guard !Task.isCancelled else { return }
            await withCheckedContinuation { continuation in
                store.delete(cookie) { continuation.resume() }
            }
        }
        guard !Task.isCancelled else { return }
        availableCookies.removeAll()
        updateTransferAvailability()
    }

    private func refreshCookies() {
        guard messageWebViewController == nil, let store = observedCookieStore else { return }
        let generation = transferGeneration
        store.getAllCookies { [weak self] cookies in
            DispatchQueue.main.async {
                guard let self, self.transferGeneration == generation,
                      self.messageWebViewController == nil else { return }
                self.availableCookies = cookies.filter(self.isAllowedCookie)
                self.updateTransferAvailability()
            }
        }
    }

    private func isAllowedCookie(_ cookie: HTTPCookie) -> Bool {
        HackerNewsCookieCapture.isEligible(cookie)
    }

    private var authenticationCookie: HTTPCookie? {
        HackerNewsCookieCapture.authenticationCookie(in: availableCookies)
    }

    private var hasAuthenticationCookie: Bool {
        authenticationCookie != nil
    }

    private func updateTransferAvailability() {
        setTransferPanelVisible(hasAuthenticationCookie && !suppressAutomaticTransfer)
        transfer.cookiesChanged(availableCookies)
    }

    private func showTransferState(_ state: MessagesCookieTransfer.State) {
        // WebView-only cards keep their entire surface available for the page.
        guard messageWebViewController == nil else { return }
        transferStatusLabel.textColor = .secondaryLabel
        switch state {
        case .idle:
            transferStatusLabel.text = nil
        case .sending:
            transferStatusLabel.text = "Connecting your session…"
        case .retrying:
            transferStatusLabel.text = "Connection interrupted. Retrying…"
        case .succeeded(_, let count):
            transferStatusLabel.textColor = .systemGreen
            transferStatusLabel.text = count.map { "Sent \($0) cookies. Session connected." } ?? "Session connected."
        case .failed(let message):
            transferStatusLabel.textColor = .systemRed
            transferStatusLabel.text = message
        }
    }

    private func setTransferPanelVisible(_ visible: Bool) {
        guard messageWebViewController == nil else { return }
        transferPanel.isHidden = !visible
        guard let withPanel = webViewTopWithTransferPanel,
              let withoutPanel = webViewTopWithoutTransferPanel else {
            return
        }

        if visible {
            withoutPanel.isActive = false
            withPanel.isActive = true
        } else {
            withPanel.isActive = false
            withoutPanel.isActive = true
        }
    }

    private func presentInsertionError(_ error: Error) {
        let alert = UIAlertController(
            title: "Couldn't Add Card",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentPreparedSession(_ preparation: PreparedTransfer) {
        if let inspectorURL = preparation.inspectorURL {
            UIPasteboard.general.url = inspectorURL
        }
        let alert = UIAlertController(
            title: "Recorded Session Ready",
            message: preparation.inspectorURL == nil
                ? "Open the Browserbase session in the dashboard, then send and tap the card."
                : "The live Browserbase view link was copied. Paste it on your Mac, start recording, then send and tap the card.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension MessagesViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              WebViewMessageLink.allowsNavigation(to: url) else {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        backButton.isEnabled = webView.canGoBack
        refreshCookies()
    }
}

extension MessagesViewController: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        refreshCookies()
    }
}
