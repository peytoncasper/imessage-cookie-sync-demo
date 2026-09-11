# Original cookie inspector

This is the earlier SwiftUI cookie-inspection prototype. It is not included in
any current Xcode target and does not implement the signed-card login flow.

`CookieInspectorView` uses `BrowserModel` to navigate a general HTTPS WebView and
show cookie prefixes. The prototype also contains a client for the legacy SMS
handoff API. Treat it as reference source; the supported app entry point is
`Shared/AppClipLoginView.swift`, and the primary experience is the iMessage app.
