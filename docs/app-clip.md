# Optional App Clip

The App Clip and host app use the same signed-card contract as the iMessage
webpage flow. Their WebView cookie store is separate from Safari. Target-only
links and the older `/open?h=...` SMS handoffs do not authorize this flow.

## Local device test

1. Configure your backend and `Config/Local.xcconfig` using the root quick start.
2. Select **CookieClip** in Xcode and run it on a connected development iPhone
   to cache the clip. Without a signed invocation it asks for a sign-in card.
3. In iPhone Settings → Developer → Local Experiences, register your HTTPS
   backend prefix and `<APP_BUNDLE_IDENTIFIER>.Clip`. Supply the required card
   title, subtitle, action, and header image.
4. Prepare a fresh URL using `Scripts/prepare_card.py`. Open its App Clip card
   through the registered local experience, or use a QR code containing the URL.
5. Sign in and verify the Browserbase session printed by the preparation script.

For a debugger launch, add `_XCAppClipURL` containing a fresh signed URL in a
local Xcode scheme's Run environment. Do not commit it. There is deliberately no
expired or target-only test grant in the shared scheme.

`AppClipInvocation` accepts `/open` on the configured backend, or Apple's
`https://appclip.apple.com/id` URL with `p=<APP_BUNDLE_IDENTIFIER>.Clip` and the
same signed-card parameters. The expected bundle ID comes from build settings.

## Optional Linq delivery

The existing helper sends a real message and prepares a Browserbase session.
Use it only when you intend those actions:

```sh
export PUBLIC_BASE_URL=https://your-project.vercel.app
python3 Scripts/send_appclip_test.py --chat YOUR_LINQ_CHAT_UUID
# Prompts privately for APP_TRANSFER_SECRET and LINQ_API_KEY when not in the environment.
```

The default sends an App Clip part. `--local` sends a text URL for development
Local Experiences. Local registration applies only to that iPhone and does not
activate a public App Clip experience.

## Public launch status

Local builds have been verified. Public, on-demand launch through Linq has not.
It requires a signed host app containing the clip, matching Associated Domains,
a valid AASA response, and an approved App Clip experience in App Store Connect.
The launch card is system UI; the webpage opens after launching the clip.

See [deployment notes](deployment.md). A local successful build does not confirm
App Store review, invocation previews, or public distribution.
