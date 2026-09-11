import { describe, expect, it } from "vitest";

import { parseCookiePayload } from "../src/cookies.js";
import { AppError } from "../src/errors.js";

const sessionId = "30c3cc0d-31d0-4b8e-b088-fca72b5ff5d9";

describe("parseCookiePayload", () => {
  it("normalizes a useful cookie payload", () => {
    const result = parseCookiePayload({
      sessionId,
      cookies: [{
        name: "session_id",
        value: "secret-value",
        url: "https://app.example.com/account",
        path: "/",
        secure: true,
        httpOnly: true,
        sameSite: "Lax",
        expires: "2030-01-01T00:00:00.000Z",
      }],
    }, "example.com");

    expect(result.sessionId).toBe(sessionId);
    expect(result.cookies[0]).toMatchObject({
      name: "session_id",
      value: "secret-value",
      url: "https://app.example.com/account",
      path: "/",
      secure: true,
      httpOnly: true,
      sameSite: "Lax",
      expires: 1_893_456_000,
    });
  });

  it("rejects a domain outside the allowlist", () => {
    expect(() => parseCookiePayload({
      sessionId,
      cookies: [{ name: "sid", value: "value", domain: ".evil.example" }],
    }, "trusted.example")).toThrowError(AppError);
  });

  it("enforces modern cookie prefix rules", () => {
    expect(() => parseCookiePayload({
      sessionId,
      cookies: [{
        name: "__Host-session",
        value: "value",
        domain: "example.com",
        path: "/",
        secure: true,
      }],
    })).toThrowError(AppError);
  });

  it("requires Secure for SameSite=None", () => {
    expect(() => parseCookiePayload({
      sessionId,
      cookies: [{
        name: "sid",
        value: "value",
        domain: "example.com",
        sameSite: "None",
      }],
    })).toThrowError(AppError);
  });

  it("rejects duplicate cookie identities", () => {
    expect(() => parseCookiePayload({
      sessionId,
      cookies: [
        { name: "sid", value: "one", domain: "example.com" },
        { name: "sid", value: "two", domain: ".example.com", path: "/" },
      ],
    })).toThrowError(AppError);
  });

  it("fails closed when the domain allowlist is malformed", () => {
    expect(() => parseCookiePayload({
      sessionId,
      cookies: [{ name: "sid", value: "one", domain: "example.com" }],
    }, "not a domain")).toThrowError(AppError);
  });
});
