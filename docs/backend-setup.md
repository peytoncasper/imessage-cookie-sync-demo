# Backend setup

The native app needs an HTTPS deployment of `vercel-cookie-loader`. You supply
your own Browserbase and Vercel accounts. The default `cookieclip.example` host
is a placeholder and never points at somebody else's demo backend.

## Configure the service

Create a Vercel project with **Root Directory** set to `vercel-cookie-loader`.
Copy `.env.example` to `.env.local` for local development, or use the file created
by `make setup`. Local files are ignored by Git; Vercel deployment variables must
also be set in the project settings.

For the main sign-in flow, configure:

| Variable | Value |
| --- | --- |
| `BROWSERBASE_API_KEY` | Your Browserbase API key |
| `BROWSERBASE_PROJECT_ID` | Your Browserbase project ID |
| `COOKIE_INGEST_SECRET` | Random secret, at least 32 characters; signs session grants |
| `APP_TRANSFER_SECRET` | Separate random secret, at least 32 characters; authorizes preparation |
| `COOKIE_DOMAIN_ALLOWLIST` | `ycombinator.com` for this native demo |

Run `openssl rand -hex 32` separately for each secret. Keep these on your backend
and trusted development machine. Do not add them to `project.yml` or tracked
configuration. `ALLOWED_ORIGIN` is optional and only needed for cross-origin
browser API clients.

Deploy from the Vercel dashboard, or run `vercel` from `vercel-cookie-loader` after
installing and authenticating the Vercel CLI. A production deployment is an
explicit action: `vercel --prod`.

## Verify

```sh
export PUBLIC_BASE_URL=https://your-project.vercel.app
curl --fail "$PUBLIC_BASE_URL/api/health"
python3 Scripts/prepare_card.py --output .local/first-card.txt
```

The health endpoint checks reachability, not upstream credentials. Successful
card preparation verifies the preparation secret and Browserbase connection and
creates a recorded, ten-minute session. The script writes a private URL file and
prints the session ID and grant expiration without printing the token.

Set `BACKEND_DOMAIN` in `Config/Local.xcconfig` to this same hostname, then
follow the [iMessage flow](../README.md#connect-a-real-session).

## Local API development

```sh
cd vercel-cookie-loader
npm ci
# With an installed, authenticated Vercel CLI:
vercel dev
npm test
npm run build
```

Native cards require HTTPS and the configured origin; use a deployed development
backend for device tests. Do not weaken the URL checks to accept arbitrary HTTP
links. Backend tests mock upstream calls and do not require a live deployment.

The [API reference](../vercel-cookie-loader/README.md) describes the preparation,
upload, and health endpoints.
