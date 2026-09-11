import { afterEach, describe, expect, it, vi } from "vitest";

import { parsePhoneNumber, sendText } from "../src/twilio.js";

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("parsePhoneNumber", () => {
  it("accepts E.164 phone numbers", () => {
    expect(parsePhoneNumber("+14155550123")).toBe("+14155550123");
  });

  it("rejects formatted or local phone numbers", () => {
    expect(() => parsePhoneNumber("(415) 555-0123")).toThrow();
    expect(() => parsePhoneNumber("4155550123")).toThrow();
  });
});

describe("sendText", () => {
  it("uses Account SID and Auth Token when no API key pair is configured", async () => {
    const accountSid = `AC${"a".repeat(32)}`;
    const authToken = "test-auth-token";
    vi.stubEnv("TWILIO_ACCOUNT_SID", accountSid);
    vi.stubEnv("TWILIO_AUTH_TOKEN", authToken);
    vi.stubEnv("TWILIO_MESSAGING_SERVICE_SID", `MG${"b".repeat(32)}`);
    vi.stubEnv("TWILIO_API_KEY_SID", "");
    vi.stubEnv("TWILIO_API_KEY_SECRET", "");

    const fetchMock = vi.fn().mockResolvedValue(Response.json({
      sid: `SM${"c".repeat(32)}`,
      status: "queued",
    }, { status: 201 }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(sendText("+14155550123", "Test message")).resolves.toMatchObject({
      status: "queued",
    });

    const options = fetchMock.mock.calls[0]?.[1] as RequestInit;
    const authorization = (options.headers as Record<string, string>).Authorization;
    expect(authorization).toBe(
      `Basic ${Buffer.from(`${accountSid}:${authToken}`).toString("base64")}`,
    );
  });

  it("uses Textbelt when selected for temporary testing", async () => {
    vi.stubEnv("SMS_PROVIDER", "textbelt");
    vi.stubEnv("TEXTBELT_API_KEY", "textbelt");
    const fetchMock = vi.fn().mockResolvedValue(Response.json({
      success: true,
      textId: 12345,
      quotaRemaining: 0,
    }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(sendText("+14155550123", "Cookie Clip: Test"))
      .resolves.toEqual({ sid: "textbelt:12345", status: "accepted" });

    expect(fetchMock).toHaveBeenCalledWith(
      "https://textbelt.com/text",
      expect.objectContaining({ method: "POST" }),
    );
    const options = fetchMock.mock.calls[0]?.[1] as RequestInit;
    expect(String(options.body)).toContain("key=textbelt");
  });
});
