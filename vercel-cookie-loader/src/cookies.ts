import type { Protocol } from "puppeteer-core";

import { AppError } from "./errors.js";

const MAX_COOKIES = 100;
const MAX_NAME_LENGTH = 256;
const MAX_VALUE_LENGTH = 16_384;
const COOKIE_NAME = /^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/;
const DOMAIN = /^(?:\.?)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i;

const sameSites = new Set(["Strict", "Lax", "None"]);
const priorities = new Set(["Low", "Medium", "High"]);
const sourceSchemes = new Set(["Unset", "NonSecure", "Secure"]);

export interface IncomingCookie {
  name?: unknown;
  value?: unknown;
  url?: unknown;
  domain?: unknown;
  path?: unknown;
  secure?: unknown;
  httpOnly?: unknown;
  sameSite?: unknown;
  expires?: unknown;
  priority?: unknown;
  sourceScheme?: unknown;
  sourcePort?: unknown;
}

export interface CookiePayload {
  sessionId: string;
  cookies: Protocol.Network.CookieParam[];
}

function fail(field: string, message: string): never {
  throw new AppError(400, "BAD_REQUEST", "Invalid request body.", { field, message });
}

function normalizedDomain(input: string): string {
  return input.trim().toLowerCase().replace(/^\./, "");
}

function domainFromCookie(cookie: IncomingCookie, field: string): string {
  if (typeof cookie.url === "string") {
    let parsed: URL;
    try {
      parsed = new URL(cookie.url);
    } catch {
      fail(`${field}.url`, "must be a valid HTTP(S) URL");
    }
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      fail(`${field}.url`, "must use http or https");
    }
    return parsed.hostname.toLowerCase();
  }

  if (typeof cookie.domain === "string" && DOMAIN.test(cookie.domain)) {
    return normalizedDomain(cookie.domain);
  }

  fail(field, "must include a valid url or domain");
}

function isAllowedDomain(domain: string, allowlist: string[]): boolean {
  return allowlist.some((allowed) => domain === allowed || domain.endsWith(`.${allowed}`));
}

function parseExpiry(value: unknown, field: string): number | undefined {
  if (value === undefined || value === null) return undefined;

  if (typeof value === "number" && Number.isFinite(value) && value >= 0) return value;

  if (typeof value === "string") {
    const milliseconds = Date.parse(value);
    if (Number.isFinite(milliseconds)) return milliseconds / 1000;
  }

  return fail(field, "must be epoch seconds or an ISO-8601 date string");
}

function optionalBoolean(value: unknown, field: string): boolean | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "boolean") fail(field, "must be a boolean");
  return value;
}

function optionalEnum<T extends string>(
  value: unknown,
  values: Set<string>,
  field: string,
): T | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "string" || !values.has(value)) {
    fail(field, `must be one of: ${[...values].join(", ")}`);
  }
  return value as T;
}

function parseCookie(
  input: unknown,
  index: number,
  allowlist: string[],
): Protocol.Network.CookieParam {
  const field = `cookies[${index}]`;
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    fail(field, "must be an object");
  }

  const cookie = input as IncomingCookie;
  if (
    typeof cookie.name !== "string" ||
    cookie.name.length === 0 ||
    cookie.name.length > MAX_NAME_LENGTH ||
    !COOKIE_NAME.test(cookie.name)
  ) {
    fail(`${field}.name`, "contains unsupported characters or has an invalid length");
  }
  if (typeof cookie.value !== "string" || cookie.value.length > MAX_VALUE_LENGTH) {
    fail(`${field}.value`, `must be a string no longer than ${MAX_VALUE_LENGTH} characters`);
  }

  const domain = domainFromCookie(cookie, field);
  if (allowlist.length > 0 && !isAllowedDomain(domain, allowlist)) {
    fail(field, `domain ${domain} is not allowed`);
  }

  if (cookie.url !== undefined && typeof cookie.url !== "string") {
    fail(`${field}.url`, "must be a string");
  }
  if (cookie.domain !== undefined && (typeof cookie.domain !== "string" || !DOMAIN.test(cookie.domain))) {
    fail(`${field}.domain`, "must be a valid hostname");
  }
  if (cookie.path !== undefined && (typeof cookie.path !== "string" || !cookie.path.startsWith("/"))) {
    fail(`${field}.path`, "must start with /");
  }
  if (cookie.sourcePort !== undefined && (
    typeof cookie.sourcePort !== "number" ||
    !Number.isInteger(cookie.sourcePort) ||
    cookie.sourcePort < -1 ||
    cookie.sourcePort > 65_535
  )) {
    fail(`${field}.sourcePort`, "must be an integer from -1 through 65535");
  }

  const secure = optionalBoolean(cookie.secure, `${field}.secure`);
  const sameSite = optionalEnum<Protocol.Network.CookieSameSite>(
    cookie.sameSite,
    sameSites,
    `${field}.sameSite`,
  );

  if (sameSite === "None" && secure !== true) {
    fail(field, "SameSite=None cookies must set secure=true");
  }
  if (cookie.name.startsWith("__Secure-") && secure !== true) {
    fail(field, "__Secure- cookies must set secure=true");
  }
  if (cookie.name.startsWith("__Host-") && (
    secure !== true ||
    cookie.path !== "/" ||
    cookie.domain !== undefined ||
    typeof cookie.url !== "string"
  )) {
    fail(field, "__Host- cookies require secure=true, path=/, url, and no domain");
  }

  const result: Protocol.Network.CookieParam = {
    name: cookie.name,
    value: cookie.value,
  };

  if (typeof cookie.url === "string") result.url = cookie.url;
  if (typeof cookie.domain === "string") result.domain = cookie.domain;
  result.path = typeof cookie.path === "string" ? cookie.path : "/";

  const expires = parseExpiry(cookie.expires, `${field}.expires`);
  const httpOnly = optionalBoolean(cookie.httpOnly, `${field}.httpOnly`);
  const priority = optionalEnum<Protocol.Network.CookiePriority>(
    cookie.priority,
    priorities,
    `${field}.priority`,
  );
  const sourceScheme = optionalEnum<Protocol.Network.CookieSourceScheme>(
    cookie.sourceScheme,
    sourceSchemes,
    `${field}.sourceScheme`,
  );

  if (secure !== undefined) result.secure = secure;
  if (httpOnly !== undefined) result.httpOnly = httpOnly;
  if (sameSite !== undefined) result.sameSite = sameSite;
  if (expires !== undefined) result.expires = expires;
  if (priority !== undefined) result.priority = priority;
  if (sourceScheme !== undefined) result.sourceScheme = sourceScheme;
  if (typeof cookie.sourcePort === "number") result.sourcePort = cookie.sourcePort;

  return result;
}

function parseAllowlist(value: string | undefined): string[] {
  if (!value) return [];
  const domains = value
    .split(",")
    .map((domain) => domain.trim())
    .filter(Boolean)
    .map(normalizedDomain)
  if (domains.some((domain) => !DOMAIN.test(domain))) {
    throw new AppError(
      500,
      "CONFIGURATION_ERROR",
      "COOKIE_DOMAIN_ALLOWLIST contains an invalid domain.",
    );
  }
  return domains;
}

export function parseCookiePayload(body: unknown, allowlistValue?: string): CookiePayload {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    fail("body", "must be a JSON object");
  }

  const record = body as Record<string, unknown>;
  if (
    typeof record.sessionId !== "string" ||
    !/^[A-Za-z0-9_-]{1,128}$/.test(record.sessionId)
  ) {
    fail("sessionId", "must be a valid Browserbase session ID");
  }
  if (!Array.isArray(record.cookies) || record.cookies.length === 0) {
    fail("cookies", "must be a non-empty array");
  }
  if (record.cookies.length > MAX_COOKIES) {
    fail("cookies", `cannot contain more than ${MAX_COOKIES} cookies`);
  }

  const allowlist = parseAllowlist(allowlistValue);
  const cookies = record.cookies.map((cookie, index) => parseCookie(cookie, index, allowlist));
  const identities = new Set<string>();
  for (const [index, cookie] of cookies.entries()) {
    const descriptor = cookieDescriptor(cookie);
    const identity = `${descriptor.name}\u0000${normalizedDomain(descriptor.domain)}\u0000${descriptor.path}`;
    if (identities.has(identity)) {
      fail(`cookies[${index}]`, "duplicates another cookie name/domain/path tuple");
    }
    identities.add(identity);
  }

  return {
    sessionId: record.sessionId,
    cookies,
  };
}

export function cookieDescriptor(cookie: Protocol.Network.CookieParam): {
  name: string;
  domain: string;
  path: string;
} {
  const domain = cookie.domain ?? (cookie.url ? new URL(cookie.url).hostname : "");
  return {
    name: cookie.name,
    domain,
    path: cookie.path ?? "/",
  };
}
