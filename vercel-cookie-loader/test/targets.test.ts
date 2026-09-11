import { describe, expect, it } from "vitest";

import { parseTargetURL, publicBaseURL } from "../src/targets.js";

describe("parseTargetURL", () => {
  it("accepts HTTPS subdomains in the allowlist", () => {
    expect(parseTargetURL("https://login.example.com/start#fragment", "example.com"))
      .toBe("https://login.example.com/start");
  });

  it("rejects HTTP and domains outside the allowlist", () => {
    expect(() => parseTargetURL("http://example.com", "example.com")).toThrow();
    expect(() => parseTargetURL("https://example.net", "example.com")).toThrow();
  });

  it("fails closed for malformed allowlist configuration", () => {
    expect(() => parseTargetURL("https://example.com", "not a domain")).toThrow();
  });
});

describe("publicBaseURL", () => {
  it("normalizes the configured origin", () => {
    expect(publicBaseURL("https://links.example.com/path?q=1").toString())
      .toBe("https://links.example.com/");
  });
});
