import { describe, expect, it } from "vitest";

import { bearerToken, hasValidBearerToken } from "../src/auth.js";

describe("hasValidBearerToken", () => {
  it("accepts an exact bearer token", () => {
    expect(hasValidBearerToken("Bearer secret", "secret")).toBe(true);
  });

  it("rejects missing and different tokens", () => {
    expect(hasValidBearerToken(undefined, "secret")).toBe(false);
    expect(hasValidBearerToken("Bearer wrong", "secret")).toBe(false);
    expect(hasValidBearerToken("Basic secret", "secret")).toBe(false);
  });

  it("extracts only a non-empty bearer token", () => {
    expect(bearerToken("Bearer short-lived-token")).toBe("short-lived-token");
    expect(bearerToken("Bearer ")).toBeUndefined();
    expect(bearerToken("Basic short-lived-token")).toBeUndefined();
  });
});
