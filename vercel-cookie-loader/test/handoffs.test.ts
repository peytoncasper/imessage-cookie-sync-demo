import { afterEach, describe, expect, it, vi } from "vitest";

import {
  createHandoff,
  enforceRecipientRateLimit,
  redeemHandoff,
} from "../src/handoffs.js";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("encrypted handoffs", () => {
  it("round-trips a target without external storage", async () => {
    vi.stubEnv("HANDOFF_SECRET", "a-test-secret-that-is-at-least-32-characters-long");
    const targetUrl = "https://example.com/login?flow=demo";
    const created = await createHandoff(targetUrl);

    expect(created.id).toMatch(/^v1\./);
    expect(created.id).not.toContain("example.com");
    await expect(redeemHandoff(created.id)).resolves.toMatchObject({ targetUrl });
    await expect(redeemHandoff(created.id)).rejects.toMatchObject({
      code: "HANDOFF_NOT_FOUND",
    });
  });

  it("rejects tampered tokens", async () => {
    vi.stubEnv("HANDOFF_SECRET", "another-test-secret-that-is-at-least-32-characters");
    const created = await createHandoff("https://example.com/");
    const replacement = created.id.endsWith("A") ? "B" : "A";

    await expect(redeemHandoff(`${created.id.slice(0, -1)}${replacement}`))
      .rejects.toMatchObject({ code: "HANDOFF_NOT_FOUND" });
  });
});

describe("in-memory recipient limits", () => {
  it("allows three sends and rejects the fourth", async () => {
    const phone = "+14155550999";
    await enforceRecipientRateLimit(phone);
    await enforceRecipientRateLimit(phone);
    await enforceRecipientRateLimit(phone);
    await expect(enforceRecipientRateLimit(phone)).rejects.toMatchObject({
      code: "RATE_LIMITED",
    });
  });
});
