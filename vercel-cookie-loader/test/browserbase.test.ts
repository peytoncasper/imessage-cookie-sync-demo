import { afterEach, expect, it, vi } from "vitest";
import { createBrowserbaseSession } from "../src/browserbase.js";

afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });

it("creates an isolated Browserbase session for every prepared sign-in", async () => {
  let created = 0;
  vi.stubEnv("BROWSERBASE_PROJECT_ID", "test-project");
  const mockFetch = vi.fn(async (url: string, options?: RequestInit) => {
    if (url.endsWith("/debug")) return Response.json({ debuggerFullscreenUrl: "https://debug.example" });
    expect(url).toBe("https://api.browserbase.com/v1/sessions");
    expect(options?.method).toBe("POST");
    expect(JSON.parse(options!.body as string)).toMatchObject({ projectId: "test-project", keepAlive: true });
    return Response.json({ id: `session-${++created}`, status: "RUNNING", expiresAt: "2030-01-01T00:00:00Z" });
  });
  vi.stubGlobal("fetch", mockFetch);
  const first = await createBrowserbaseSession("synthetic-api-key");
  const second = await createBrowserbaseSession("synthetic-api-key");
  expect(first.id).not.toBe(second.id);
  expect(created).toBe(2);
});
