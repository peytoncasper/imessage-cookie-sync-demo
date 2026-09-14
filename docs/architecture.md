# Architecture

The Messages extension contains the browser, card validation, and cookie
capture code. The Messages controller owns presentation and composition;
`MessagesCookieTransfer` owns network requests, retries, cancellation, and
completion state.

```mermaid
sequenceDiagram
    participant Developer as Trusted sender
    participant API as Vercel API
    participant BB as Browserbase
    participant Messages as iMessage extension
    Developer->>API: Prepare with APP_TRANSFER_SECRET
    API->>BB: Create a fresh session
    API-->>Developer: Session ID and 10-minute grant
    Developer->>Messages: Paste URL, Add Card, manually send
    Messages->>Messages: Open isolated Hacker News WebView
    Messages->>API: Eligible cookies and scoped grant
    API->>BB: Inject cookies, navigate to Hacker News
    API-->>Messages: Matching session ID and injected count
```

## Native responsibilities

- `MessagesViewController`: active conversation, selected card, compact/expanded
  presentation, and card insertion.
- `MessageWebViewController`: isolated webpage, loading/retry UI, navigation
  allowlist, and cookie-store observation.
- `WebViewMessageLink` / `SignInCard`: URL and signed-card claim validation.
- `HackerNewsCookieCapture`: eligible domain/expiry filtering and auth fingerprint.
- `MessagesCookieTransfer`: optional preparation, scoped upload, bounded retries,
  deduplication, and cancellation when inactive or switching cards.

Webpage cards use a nonpersistent cookie store. The older Messages demo UI uses
its own persistent store. Neither can inspect Safari's store. Only eligible
Hacker News cookies are uploaded after detecting the `user` authentication cookie.

The transfer coordinator rejects upload redirects and requires matching server
responses. A cancellation invalidates local callbacks; it cannot undo a request
already processed by a remote service.

## Backend responsibilities

`/api/transfers/prepare` creates a new recorded Browserbase session for each
card. It never borrows another user's running session. `/api/cookies` validates
the grant or administrator credential, filters the payload, injects via CDP,
and returns metadata without cookie values.

Transfer grant consumption uses process memory. It is best-effort across
serverless instances and is not atomic across concurrent requests. Public
multi-user service requires shared durable state plus an authenticated
preparation flow.
