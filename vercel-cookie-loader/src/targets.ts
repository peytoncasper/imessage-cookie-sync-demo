import { AppError } from "./errors.js";

const DOMAIN = /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i;

function parseAllowlist(value: string | undefined): string[] {
  if (!value) return [];

  const domains = value
    .split(",")
    .map((domain) => domain.trim().toLowerCase().replace(/^\./, ""))
    .filter(Boolean);

  if (domains.some((domain) => !DOMAIN.test(domain))) {
    throw new AppError(
      500,
      "CONFIGURATION_ERROR",
      "TARGET_DOMAIN_ALLOWLIST contains an invalid domain.",
    );
  }
  return domains;
}

export function parseTargetURL(input: unknown, allowlistValue?: string): string {
  if (typeof input !== "string" || input.length === 0 || input.length > 2_048) {
    throw new AppError(400, "BAD_REQUEST", "targetUrl must be a valid HTTPS URL.");
  }

  let url: URL;
  try {
    url = new URL(input);
  } catch {
    throw new AppError(400, "BAD_REQUEST", "targetUrl must be a valid HTTPS URL.");
  }

  if (url.protocol !== "https:" || url.username || url.password) {
    throw new AppError(400, "BAD_REQUEST", "targetUrl must be a valid HTTPS URL.");
  }

  const allowlist = parseAllowlist(allowlistValue);
  const hostname = url.hostname.toLowerCase();
  if (
    allowlist.length > 0 &&
    !allowlist.some((domain) => hostname === domain || hostname.endsWith(`.${domain}`))
  ) {
    throw new AppError(400, "BAD_REQUEST", "The target URL domain is not allowed.");
  }

  url.hash = "";
  return url.toString();
}

export function publicBaseURL(value: string | undefined): URL {
  if (!value) {
    throw new AppError(500, "CONFIGURATION_ERROR", "PUBLIC_BASE_URL is missing.");
  }

  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new AppError(500, "CONFIGURATION_ERROR", "PUBLIC_BASE_URL is invalid.");
  }

  if (url.protocol !== "https:" && !(url.protocol === "http:" && url.hostname === "localhost")) {
    throw new AppError(500, "CONFIGURATION_ERROR", "PUBLIC_BASE_URL must use HTTPS.");
  }

  url.pathname = "/";
  url.search = "";
  url.hash = "";
  return url;
}
