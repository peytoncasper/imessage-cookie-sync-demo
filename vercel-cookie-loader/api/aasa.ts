import { appleIdentifiers } from "../src/apple.js";

export default {
  fetch(): Response {
    const identifiers = appleIdentifiers();
    if (!identifiers) {
      return Response.json({ error: "Configure APPLE_TEAM_ID and APP_BUNDLE_IDENTIFIER." },
        { status: 503, headers: { "Cache-Control": "no-store" } });
    }
    return Response.json({
      applinks: { apps: [], details: [{ appID: identifiers.appID, paths: ["/open"] }] },
      appclips: { apps: [identifiers.clipID] },
    }, {
      headers: {
        "Cache-Control": "public, max-age=300",
        "X-Content-Type-Options": "nosniff",
      },
    });
  },
};
