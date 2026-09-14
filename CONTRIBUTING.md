# Contributing

Run `make setup`, edit only your ignored local configuration, and run
`make check` before submitting changes. Changes to native UI or target membership
also need `make build-simulator`. Device presentation, clipboard behavior, and
live Browserbase transfers require a separate smoke test; report what was
actually verified.

`project.yml` is the source of truth for Xcode target membership. Run
`make generate` after changing it and include the generated project changes.
Build configuration uses XcodeGen's
[configuration-file support](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md#config-files).
Shared Swift code belongs in `Shared/`, not inside an extension target's folder.

Keep account settings in `Config/Local.xcconfig` and backend credentials in
`vercel-cookie-loader/.env.local`. Do not commit prepared card URLs, signed
builds, live recordings, `.vercel` state, or dependency directories. Tests should
use synthetic tokens and mocked services, and must not send messages or create
paid sessions.

The CI workflow runs backend/Python checks on Linux and native checks plus a
Simulator build on macOS; no live credentials are needed.
