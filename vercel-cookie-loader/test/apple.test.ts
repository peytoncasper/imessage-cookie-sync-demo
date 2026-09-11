import { afterEach, describe, expect, it, vi } from "vitest";
import aasa from "../api/aasa.js";
import open from "../api/open.js";

afterEach(() => vi.unstubAllEnvs());

describe("portable Apple configuration", () => {
  it("uses the configured identifiers for both association and launch metadata", async () => {
    vi.stubEnv("APPLE_TEAM_ID", "TESTTEAM12");
    vi.stubEnv("APP_BUNDLE_IDENTIFIER", "org.test.Login");
    expect(await aasa.fetch().json()).toEqual({
      applinks: { apps: [], details: [{ appID: "TESTTEAM12.org.test.Login", paths: ["/open"] }] },
      appclips: { apps: ["TESTTEAM12.org.test.Login.Clip"] },
    });
    expect(await open.fetch().text()).toContain("app-clip-bundle-id=org.test.Login.Clip");
  });
  it("does not publish an invalid association or interpolate arbitrary HTML", async () => {
    vi.stubEnv("APPLE_TEAM_ID", "");
    vi.stubEnv("APP_BUNDLE_IDENTIFIER", '\"><script>');
    expect(aasa.fetch().status).toBe(503);
    expect(await open.fetch().text()).not.toContain("apple-itunes-app");
  });
});
