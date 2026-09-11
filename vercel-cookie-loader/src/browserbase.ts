import puppeteer, { type Browser, type CDPSession, type Protocol } from "puppeteer-core";

import { AppError } from "./errors.js";

interface BrowserbaseSession {
  id: string;
  status: string;
  connectUrl: string;
  projectId: string;
  expiresAt?: string;
  userMetadata?: Record<string, string>;
}

export interface CreatedBrowserbaseSession {
  id: string;
  expiresAt: string;
  inspectorUrl: string;
}

async function sessionInspectorUrl(sessionId: string, apiKey: string): Promise<string> {
  try {
    const response = await fetch(
      `https://api.browserbase.com/v1/sessions/${encodeURIComponent(sessionId)}/debug`,
      {
        headers: { "X-BB-API-Key": apiKey },
        signal: AbortSignal.timeout(8_000),
      },
    );
    if (response.ok) {
      const debug = await response.json() as { debuggerFullscreenUrl?: unknown };
      if (typeof debug.debuggerFullscreenUrl === "string") {
        return debug.debuggerFullscreenUrl;
      }
    }
  } catch {
    // Fall through to the dashboard URL if live-debug URL creation lags.
  }
  return `https://www.browserbase.com/sessions/${encodeURIComponent(sessionId)}`;
}

export interface InjectionResult {
  injected: number;
  cookies: Array<{ name: string; domain: string; path: string }>;
}

function normalizedDomain(value: string): string {
  return value.toLowerCase().replace(/^\./, "");
}

export async function createBrowserbaseSession(apiKey: string): Promise<CreatedBrowserbaseSession> {
  let response: Response;
  try {
    response = await fetch("https://api.browserbase.com/v1/sessions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-BB-API-Key": apiKey,
      },
      body: JSON.stringify({
        ...(process.env.BROWSERBASE_PROJECT_ID?.trim()
          ? { projectId: process.env.BROWSERBASE_PROJECT_ID.trim() }
          : {}),
        keepAlive: true,
        timeout: 600,
        browserSettings: {
          allowedDomains: ["ycombinator.com"],
          logSession: true,
          recordSession: true,
        },
        userMetadata: { source: "cookie_clip" },
      }),
      signal: AbortSignal.timeout(8_000),
    });
  } catch {
    throw new AppError(502, "BROWSERBASE_ERROR", "Could not create a Browserbase session.");
  }

  if (response.status === 429) {
    throw new AppError(
      409,
      "SESSION_LIMIT_REACHED",
      "The Browserbase project already has its maximum number of running sessions.",
    );
  }
  if (!response.ok) {
    throw new AppError(502, "BROWSERBASE_ERROR", "Browserbase rejected session creation.");
  }

  const session = await response.json() as Partial<BrowserbaseSession>;
  if (
    typeof session.id !== "string"
    || typeof session.expiresAt !== "string"
    || session.status !== "RUNNING"
  ) {
    throw new AppError(502, "BROWSERBASE_ERROR", "Browserbase returned an invalid session.");
  }

  return {
    id: session.id,
    expiresAt: session.expiresAt,
    inspectorUrl: await sessionInspectorUrl(session.id, apiKey),
  };
}

async function getSession(sessionId: string, apiKey: string): Promise<BrowserbaseSession> {
  let response: Response;
  try {
    response = await fetch(
      `https://api.browserbase.com/v1/sessions/${encodeURIComponent(sessionId)}`,
      {
        headers: { "X-BB-API-Key": apiKey },
        signal: AbortSignal.timeout(8_000),
      },
    );
  } catch {
    throw new AppError(502, "BROWSERBASE_ERROR", "Could not reach Browserbase.");
  }

  if (response.status === 404) {
    throw new AppError(404, "SESSION_NOT_FOUND", "Browserbase session was not found.");
  }
  if (!response.ok) {
    throw new AppError(502, "BROWSERBASE_ERROR", "Browserbase rejected the session lookup.");
  }

  const session = await response.json() as BrowserbaseSession;
  if (session.status !== "RUNNING") {
    throw new AppError(
      409,
      "SESSION_NOT_RUNNING",
      `Browserbase session is ${session.status || "not running"}.`,
    );
  }
  if (typeof session.connectUrl !== "string" || !session.connectUrl.startsWith("wss://")) {
    throw new AppError(502, "BROWSERBASE_ERROR", "Browserbase returned no CDP connection URL.");
  }

  return session;
}

export async function injectCookies(
  sessionId: string,
  cookies: Protocol.Network.CookieParam[],
  apiKey: string,
  navigateUrl?: string,
): Promise<InjectionResult> {
  const session = await getSession(sessionId, apiKey);
  let browser: Browser | undefined;
  let cdp: CDPSession | undefined;

  try {
    browser = await puppeteer.connect({
      browserWSEndpoint: session.connectUrl,
      protocolTimeout: 12_000,
    });

    const pages = await browser.pages();
    const page = pages[0] ?? await browser.newPage();
    cdp = await page.createCDPSession();
    await cdp.send("Storage.setCookies", { cookies });

    // Read back cookie metadata so a successful response means Chromium accepted
    // the command. Values are deliberately excluded from the API result.
    const stored = await cdp.send("Storage.getCookies");
    const descriptors = cookies.map((requested) => {
      const requestedDomain = requested.domain ?? new URL(requested.url!).hostname;
      const match = stored.cookies.find((candidate) => (
        candidate.name === requested.name &&
        normalizedDomain(candidate.domain) === normalizedDomain(requestedDomain) &&
        candidate.path === requested.path
      ));

      if (!match) {
        throw new AppError(502, "CDP_ERROR", "Chromium did not retain every requested cookie.");
      }

      return { name: match.name, domain: match.domain, path: match.path };
    });

    if (navigateUrl) {
      await cdp.send("Page.enable");
      const navigation = await cdp.send("Page.navigate", { url: navigateUrl });
      if (navigation.errorText) {
        throw new AppError(502, "CDP_ERROR", "Chromium could not open the signed-in page.");
      }
    }

    return { injected: cookies.length, cookies: descriptors };
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw new AppError(502, "CDP_ERROR", "Could not inject cookies into the Browserbase session.");
  } finally {
    if (cdp) await cdp.detach().catch(() => undefined);
    // disconnect() only releases this CDP client. close() would terminate the
    // caller's Browserbase session.
    browser?.disconnect();
  }
}
