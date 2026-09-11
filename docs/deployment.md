# Deployment notes

Local builds and mocked tests are not a deployment verification. Each developer
must configure their own backend, Apple identifiers, signing, and distribution.

## Apple configuration

The following values must agree:

| Local build | Backend |
| --- | --- |
| `DEVELOPMENT_TEAM` | `APPLE_TEAM_ID` |
| `APP_BUNDLE_IDENTIFIER` | `APP_BUNDLE_IDENTIFIER` |
| `APP_CLIP_DOMAIN` | Host of `PUBLIC_BASE_URL` |

The extension appends `.MessagesExtension`; the App Clip appends `.Clip`.
The backend constructs the AASA response and App Clip metadata from those
identifiers. An unconfigured AASA endpoint returns 503 rather than another
account's association.

```sh
curl --include "$PUBLIC_BASE_URL/.well-known/apple-app-site-association"
```

For App Clip distribution, enable Associated Domains, obtain matching signing
profiles, upload the host app containing the clip, and configure the `/open`
experience in App Store Connect. Verify domain validation and the actual launch
on a device. Standalone iMessage distribution also requires Apple's app review
and distribution process; this repo does not publish or install a public app.

## Before operating a multi-user service

- Replace the administrative preparation secret exchange with your intended
  user-authenticated backend flow. Release apps use scoped cards, and omit the
  optional Debug preparation credential.
- Store grant consumption and rate limits in shared durable storage with atomic
  claim operations. Current process-memory tracking is insufficient across
  serverless instances or concurrent requests.
- Set cookie and destination allowlists for your supported sites. Native code
  currently supports Hacker News only.
- Review recording, session retention, access, and consent in your own product.
  This demo creates recorded Browserbase sessions and transfers login cookies.
- Rotate any previously embedded development credential before sharing builds.
  Removing it from source does not invalidate older binaries or copies.

## Optional SMS experiment

The Twilio/Textbelt administration page and `/api/texts` endpoint create a
15-minute encrypted `/open?h=...` handoff. The current native sign-in controller
requires a ten-minute transfer grant and does not redeem these handoffs. Do not
present the older SMS flow as working native login delivery.

Using the SMS API requires separate provider credentials, `TEXT_SEND_SECRET`,
`HANDOFF_SECRET`, recipient consent, and provider setup. See the backend API
reference. Sending and deployment are manual actions; setup and tests perform
neither.
