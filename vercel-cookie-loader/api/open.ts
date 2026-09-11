import { appleIdentifiers } from "../src/apple.js";

function page(): string {
  const identifiers = appleIdentifiers();
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex,nofollow">
    ${identifiers ? `<meta name="apple-itunes-app" content="app-clip-bundle-id=${identifiers.clipBundleID}, app-clip-display=card">` : ""}
    <meta property="og:title" content="Browserbase Cookie Clip Demo">
    <meta property="og:description" content="Open the requested secure link in the App Clip.">
    <meta property="og:type" content="website">
    <title>Open Cookie Clip</title>
    <style>
      :root { color-scheme: light dark; font-family: ui-sans-serif, system-ui, sans-serif; }
      body { max-width: 36rem; margin: 14vh auto; padding: 0 1.25rem; line-height: 1.55; }
    </style>
  </head>
  <body>
    <h1>Open Cookie Clip</h1>
    <p>Open your sign-in card in Messages on an iPhone with HN Login installed.</p>
    <p>App Clip launch is also available when the developer has configured an App Clip experience.</p>
    <p>Sign-in cards expire after 10 minutes. If yours has expired, request a new card.</p>
  </body>
</html>`;
}

export default {
  fetch(): Response {
    return new Response(page(), {
      headers: {
        "Cache-Control": "no-store",
        "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",
        "Content-Type": "text/html; charset=utf-8",
        "Referrer-Policy": "no-referrer",
        "X-Content-Type-Options": "nosniff",
      },
    });
  },
};
