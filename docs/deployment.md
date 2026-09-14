# Deployment notes

Local builds and mocked tests are not a deployment verification. Each developer
must configure their own backend, Apple identifiers, signing, and distribution.

## Apple configuration

Set `DEVELOPMENT_TEAM` and `APP_BUNDLE_IDENTIFIER` in `Config/Local.xcconfig`
for your Apple account. The extension appends `.MessagesExtension` to the app's
bundle identifier. Set `BACKEND_DOMAIN` to the hostname of your HTTPS backend.

Build and distribute the **HNMessages** scheme. Distribution requires Apple's
app review and signing process; this repo does not publish or install a public
app. The backend does not need Apple identifiers or domain association files.

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
