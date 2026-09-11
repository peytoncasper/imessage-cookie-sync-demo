import { afterEach, describe, expect, it, vi } from "vitest";

import {
  consumeTransferToken,
  createTransferToken,
  verifyTransferToken,
} from "../src/transferTokens.js";

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

describe("short-lived cookie transfer tokens", () => {
  it("is session-scoped and one-time after consumption", () => {
    vi.stubEnv("COOKIE_INGEST_SECRET", "a-test-secret-that-is-at-least-32-characters-long");
    const sessionId = "test-session_123";
    const created = createTransferToken(sessionId);
    const grant = verifyTransferToken(created.token, sessionId);

    expect(created.token).toMatch(/^ct1\./);
    expect(() => verifyTransferToken(created.token, "another-session")).toThrow();
    consumeTransferToken(grant);
    expect(() => verifyTransferToken(created.token, sessionId)).toThrow();
  });

  it("rejects expired tokens", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2030-01-01T00:00:00Z"));
    vi.stubEnv("COOKIE_INGEST_SECRET", "another-test-secret-that-is-at-least-32-characters");
    const created = createTransferToken("test-session");
    vi.advanceTimersByTime(10 * 60 * 1_000 + 1);

    expect(() => verifyTransferToken(created.token, "test-session")).toThrow();
  });
});
