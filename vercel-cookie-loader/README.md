# Cookie Clip backend

A Vercel Node.js service for preparing isolated Browserbase sessions and
injecting authenticated cookie payloads through Chrome DevTools Protocol.

Start with [backend setup](../docs/backend-setup.md). The main native flow needs
Browserbase credentials and two separate secrets; it does not require an SMS
provider. Use Node 22 and install dependencies with `npm ci`.

## Prepare a sign-in card

`POST /api/transfers/prepare`, authorized with `APP_TRANSFER_SECRET`, creates a
fresh recorded ten-minute Browserbase session. It returns a ten-minute grant
scoped to that session:

```json
{
  "ok": true,
  "requestId": "request-uuid",
  "sessionId": "session-uuid",
  "inspectorUrl": "https://…",
  "token": "ct1.…",
  "tokenExpiresAt": "…",
  "sessionExpiresAt": "…"
}
```

Use `Scripts/prepare_card.py` from the repo root to build a correctly encoded
native card URL and save it to an ignored private file. This endpoint creates a
billable session; it never reuses another card's running session. Keep the
preparation credential on trusted systems. Release native clients use the
returned scoped grant, not that credential.

## Upload cookies

`POST /api/cookies` accepts the scoped grant, or the administrator
`COOKIE_INGEST_SECRET`, in the `Authorization: Bearer ...` header.

```json
{
  "sessionId": "30c3cc0d-31d0-4b8e-b088-fca72b5ff5d9",
  "cookies": [
    {
      "name": "user",
      "value": "synthetic-example-only",
      "domain": "news.ycombinator.com",
      "path": "/",
      "secure": true,
      "httpOnly": true
    }
  ]
}
```

Each cookie requires `name`, `value`, and either `url` or `domain`. Optional
attributes include `path`, `secure`, `httpOnly`, `sameSite`, `expires`, `priority`,
`sourceScheme`, and `sourcePort`. Expiration accepts Unix seconds or an ISO-8601
string. Set `COOKIE_DOMAIN_ALLOWLIST=ycombinator.com` for this demo.

The service requires a running Browserbase session, injects with
`Storage.setCookies`, reads metadata back, and disconnects its CDP client without
closing the session. Grant-authenticated uploads navigate to Hacker News.
Responses contain `ok`, `requestId`, `sessionId`, `injected`, and cookie metadata;
they omit cookie values.

A grant is marked consumed after a successful upload. Consumption is currently
in process memory: it is best-effort across instances and not atomic across
concurrent requests. Use shared atomic storage before relying on globally
single-use grants. See [deployment notes](../docs/deployment.md).

## Other endpoints

| Endpoint | Purpose |
| --- | --- |
| `GET /api/health` | Reachability only; does not validate upstream credentials |
| `GET /.well-known/apple-app-site-association` | AASA from `APPLE_TEAM_ID` and `APP_BUNDLE_IDENTIFIER`; 503 if unconfigured |
| `GET /open` | Informational landing page and configured App Clip metadata |
| `POST /api/texts` | Optional older SMS experiment; sends a real text |
| `POST /api/handoffs/redeem` | Redeems the older encrypted SMS handoff |

The older SMS endpoints generate `/open?h=...` links, valid for 15 minutes. The
current native app does not redeem these links. The original client is retained
under `examples/cookie-inspector`; do not use this route as the main sign-in demo.

SMS sending requires `TEXT_SEND_SECRET`, `HANDOFF_SECRET`, `PUBLIC_BASE_URL`,
`TARGET_DOMAIN_ALLOWLIST`, and configured Twilio credentials (or optional
Textbelt mode). Requests include an E.164 `to`, HTTPS `targetUrl`, and
`consentConfirmed: true`. The root administration page provides the same form.
Recipient limits and replay detection use process memory. See `.env.example`
for the optional variables; the setup scripts never send messages.

## Development and deployment

```sh
npm ci
npm test
npm run build
# With Vercel CLI installed and authenticated:
vercel dev
```

Configure a Vercel project with Root Directory `vercel-cookie-loader` and the
environment variables in [backend setup](../docs/backend-setup.md). Deploy through
the dashboard or explicitly run `vercel --prod` from this directory. Local
`.env.local` and `.vercel/` state are ignored and not part of the shared repo.
