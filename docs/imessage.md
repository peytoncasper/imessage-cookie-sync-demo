# iMessage guide

Use the **HNMessages** scheme. It installs the standalone Messages container
and its **HNMessagesExtension**; there is no Home Screen app.

## Cards

The preferred card is prepared by a trusted backend using
`POST /api/transfers/prepare`. Its URL has this shape:

```text
https://your-project.vercel.app/open?view=web&target=ENCODED_HN_URL&bbSession=SESSION_ID&bbToken=SHORT_LIVED_TOKEN
```

`Scripts/prepare_card.py` builds the actual URL. Copy it to the iPhone clipboard
and tap **Add Card** in the extension. The extension validates the origin,
destination, token claims, and expiration, then inserts an interactive
`MSMessage`. The server verifies the token signature during upload. The user
still presses Send. A plain text URL is not itself an interactive iMessage card.

The receiving surface shows the webpage, a loading indicator, and a retry
control on load failure. Messages owns dismissal and presentation. Opening a
new card creates an isolated, nonpersistent WebView. Returning to the same card
in the same controller preserves its page. Merely rendering a card in the
transcript does not transfer cookies or request expansion.

Legacy prepared cards without `view=web` keep the older demo toolbar. A new card
created by pasting either format uses the webpage surface.

## Private Debug mode

For controlled development only, you can set `COOKIE_TRANSFER_CLIENT_SECRET`
in ignored `Config/Local.xcconfig` to your backend's `APP_TRANSFER_SECRET`. The
Debug build can then prepare a card itself when **Add Card** has no valid card
on the clipboard. The direct **Sign In** button and older unsigned webpage
cards can prepare and transfer automatically in this mode.

Unsigned webpage cards use `view=web&target=...`. They optionally accept
`presentation=compact` and a unique `test` parameter. Without the private Debug
credential, they can show the page but cannot create a Browserbase session.
Signed cards use expanded presentation. Release configuration clears the
preparation credential; use backend-prepared cards for distribution.

Secrets bundled in any Debug app can be extracted. Only install that variant
on trusted development devices.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No Home Screen icon | Expected for HNMessages; open it through a Messages conversation |
| HN Login absent from the first + menu | Swipe up within the app list to reveal the remaining apps |
| HN Login missing | Check Settings → Apps → Messages → iMessage Apps; reinstall the selected container if needed |
| Invalid or expired card | Prepare a new card; verify its hostname matches `BACKEND_DOMAIN` |
| Add Card asks for a URL | Put a fresh backend-prepared URL on the iPhone clipboard |
| Webpage works but no transfer | Use a signed card, or configure the private Debug credential |
| Backend responds 401 | Check the preparation secret or obtain a fresh, unconsumed grant |
| Backend reports session limit | End unused Browserbase sessions or wait for their expiration |

Transfer logs use the `CookieTransfer` category and `[CookieClipTransfer]`
prefix. They report successful cookie counts and session IDs without cookie
values or tokens. Check the matching session in Browserbase.

For device verification, open a fresh signed card, sign in, confirm the matching
Browserbase session, reopen the same card, switch cards during loading, and
return from a transcript preview. Automated checks cover the transfer logic;
the Messages presentation and clipboard interactions need a device smoke test.
