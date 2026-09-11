import SwiftUI
import UIKit

struct AppClipLoginView: View {
    @State private var invocationURL: URL?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AppClipLoginSurface(invocationURL: invocationURL, isActive: scenePhase == .active)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                invocationURL = activity.webpageURL
            }
            .onOpenURL { invocationURL = $0 }
            .task {
                #if DEBUG
                // Xcode/devicectl local testing only. Production uses NSUserActivity.
                if invocationURL == nil,
                   let value = ProcessInfo.processInfo.environment["_XCAppClipURL"] {
                    invocationURL = URL(string: value)
                }
                #endif
            }
    }
}

private struct AppClipLoginSurface: UIViewControllerRepresentable {
    let invocationURL: URL?
    let isActive: Bool

    func makeUIViewController(context: Context) -> AppClipLoginController { AppClipLoginController() }
    func updateUIViewController(_ controller: AppClipLoginController, context: Context) {
        controller.update(invocationURL, isActive: isActive)
    }
    static func dismantleUIViewController(_ controller: AppClipLoginController, coordinator: ()) {
        controller.stop()
    }
}

private final class AppClipLoginController: UIViewController {
    private var url: URL?
    private var browser: MessageWebViewController?
    private var transfer: AppClipCookieTransfer?
    private var isActive = false
    private let message = UILabel()
    private var baseURL: URL {
        URL(string: Bundle.main.object(forInfoDictionaryKey: "CookieClipBaseURL") as? String
            ?? "https://cookieclip.example")!
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        message.numberOfLines = 0
        message.textAlignment = .center
        message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true
        message.text = "Open your sign-in card from Messages to continue."
        message.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(message)
        NSLayoutConstraint.activate([
            message.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            message.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            message.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func update(_ newURL: URL?, isActive: Bool) {
        loadViewIfNeeded()
        self.isActive = isActive
        if let newURL, newURL != url {
            stop()
            url = newURL
            guard let invocation = AppClipInvocation.parse(newURL, baseURL: baseURL) else {
                message.text = "This sign-in card is invalid or expired. Open a fresh card to continue."
                message.isHidden = false
                UserDefaults.standard.set(["stage": "invalid_invocation", "date": Date()], forKey: "AppClipDiagnostic")
                return
            }
            let transfer = AppClipCookieTransfer(invocation: invocation, baseURL: baseURL)
            self.transfer = transfer
            let browser = MessageWebViewController()
            self.browser = browser
            browser.onCookiesChanged = { [weak self, weak browser] cookies in
                guard let self, self.isActive, self.browser === browser else { return }
                self.transfer?.cookiesChanged(cookies)
            }
            browser.onPageLoaded = {
                UserDefaults.standard.set(["stage": "page_loaded", "date": Date(), "sessionID": invocation.sessionID],
                                          forKey: "AppClipPageDiagnostic")
            }
            transfer.onStateChanged = { [weak self] state in
                guard case .failed(let reason) = state, let self, self.presentedViewController == nil else { return }
                let alert = UIAlertController(title: "Session Not Connected", message: reason, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
            message.isHidden = true
            addChild(browser)
            browser.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(browser.view)
            NSLayoutConstraint.activate([
                browser.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                browser.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                browser.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                browser.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
            browser.didMove(toParent: self)
            browser.openTarget(invocation.target)
            UserDefaults.standard.set(["stage": "opening", "date": Date(), "sessionID": invocation.sessionID],
                                      forKey: "AppClipDiagnostic")
        }
        if isActive { browser?.refreshCookies() }
    }

    func stop() {
        transfer?.stop()
        transfer = nil
        browser?.stopCapture()
        browser?.willMove(toParent: nil)
        browser?.view.removeFromSuperview()
        browser?.removeFromParent()
        browser = nil
    }
}
