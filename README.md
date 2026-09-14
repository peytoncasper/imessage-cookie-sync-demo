# HN Login

Sign in to Hacker News inside iMessage and connect that login to a Browserbase
browser session. This is a developer starter for a native login handoff: the
webpage runs in an isolated WebView, and a short-lived card authorizes the cookie
transfer. It cannot read Safari cookies.

**HN Login is a standalone iMessage app.** This repo contains the app, its
Browserbase backend, and the setup and checks needed to develop them. It is a
working demo, not a publicly distributed app or a general-purpose authentication SDK.

## Quick start

You need a Mac with full Xcode, XcodeGen, Node 22, and Python 3. Simulator builds
and automated tests need no API keys or Apple Developer account. Device signing
and live transfers require your own Apple and Browserbase accounts.

```sh
# From this repository's root:
brew install xcodegen
# If using nvm: nvm install && nvm use
make setup
make check
make build-simulator
open CookieClipDemo.xcodeproj
```

Choose the **HNMessages** scheme and an iPhone Simulator, then press **Run** to
install it. `make build-simulator` compiles the app but does not install it.
The first boot of a new simulator may take a few minutes. Open a conversation
in Messages, tap **+**, scroll up through the app list, and choose **HN Login**.
Newly installed apps may be below the first visible group. The Messages-only container has
no Home Screen app. You can open the Hacker News webpage before configuring a
backend; connecting the session requires a prepared sign-in card.

The native deployment target is iOS 17. Local verification used Xcode 26.6 and
the iOS 26.5 SDK. `make doctor` reports missing prerequisites and setup steps.

## Connect a real session

1. Follow [backend setup](docs/backend-setup.md) to deploy your own Vercel service.
2. Edit `Config/Local.xcconfig`: set your `DEVELOPMENT_TEAM`,
   `APP_BUNDLE_IDENTIFIER`, and `BACKEND_DOMAIN` (hostname only). These settings
   stay local and apply when Xcode builds. `make setup` creates the file once.
3. Install **HNMessages** on your development iPhone from Xcode.
4. Prepare a card from your Mac. This creates a billable Browserbase session,
   but does not send any messages:

   ```sh
   export PUBLIC_BASE_URL=https://your-project.vercel.app
   python3 Scripts/prepare_card.py
   # Enter APP_TRANSFER_SECRET at the hidden prompt.
   pbcopy < .local/sign-in-card.txt
   ```

5. Copy that URL to the iPhone clipboard, using Universal Clipboard if available.
   In **HN Login**, tap **Add Card**. It inserts an interactive card into the
   compose field; tap the Messages send button yourself.
6. Open the card and sign in to Hacker News. The extension transfers the eligible
   cookies to the card's Browserbase session. Find that session in your
   Browserbase dashboard using the session ID printed by the script.

Cards expire after ten minutes. For another card, run the script with a new
output path, such as `--output .local/second-card.txt`. The URL contains a bearer
grant; keep it private. Release builds do not include a preparation credential.

See [the iMessage guide](docs/imessage.md) for card formats, private Debug mode,
expected behavior, and troubleshooting.

## What is in the repo?

| Path | Purpose |
| --- | --- |
| `MessagesApp/`, `MessagesExtension/` | Standalone iMessage container, card UI, transfer coordinator |
| `Shared/` | WebView, link and signed-card validation, cookie capture |
| `vercel-cookie-loader/` | Vercel API for Browserbase preparation and cookie upload |
| `Config/`, `project.yml` | Portable Xcode settings and project generation |
| `Scripts/`, `Tests/` | Setup, card preparation, and checks without live accounts |
| `docs/` | Setup, architecture, and deployment notes |

## Common commands

| Command | Result |
| --- | --- |
| `make setup` | Install locked backend dependencies; create missing local config; generate Xcode project |
| `make doctor` | Check local tools and configuration presence |
| `make check` | Run native, Python, and backend checks without sending messages or creating sessions |
| `make build-simulator` | Build the standalone Messages app without signing |
| `make generate` | Regenerate the checked-in Xcode project from `project.yml` |
| `make clean` | Remove local `build/` output |

The backend can be developed on Linux with `npm --prefix vercel-cookie-loader ci`
and `make test-backend test-python`. Native builds require macOS.

## Deployment and current limits

- [Architecture](docs/architecture.md): card lifetimes, cookie isolation, and
  transfer behavior.
- [Deployment notes](docs/deployment.md): account configuration and limitations
  to address before a multi-user deployment.
- [Contributing](CONTRIBUTING.md): development workflow and checks.

Each prepared card gets its own Browserbase session. Replay tracking currently
uses process memory and is not a global one-use guarantee across serverless
instances.

## License

This project's source is available under the [MIT License](LICENSE).
Third-party dependencies retain their own licenses.
