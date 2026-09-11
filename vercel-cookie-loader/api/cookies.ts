import { randomUUID } from "node:crypto";

import { bearerToken, hasValidBearerToken } from "../src/auth.js";
import { injectCookies } from "../src/browserbase.js";
import { parseCookiePayload } from "../src/cookies.js";
import { AppError } from "../src/errors.js";
import {
  consumeTransferToken,
  type TransferGrant,
  verifyTransferToken,
} from "../src/transferTokens.js";

const MAX_BODY_BYTES = 256 * 1024;

function responseHeaders(request: Request): Headers {
  const headers = new Headers({
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });

  const allowedOrigin = process.env.ALLOWED_ORIGIN;
  if (allowedOrigin && request.headers.get("origin") === allowedOrigin) {
    headers.set("Access-Control-Allow-Origin", allowedOrigin);
    headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
    headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    headers.set("Vary", "Origin");
  }

  return headers;
}

function json(request: Request, body: unknown, status: number, extraHeaders?: HeadersInit): Response {
  const headers = responseHeaders(request);
  headers.set("Content-Type", "application/json; charset=utf-8");
  if (extraHeaders) {
    new Headers(extraHeaders).forEach((value, key) => headers.set(key, value));
  }
  return new Response(JSON.stringify(body), { status, headers });
}

async function readJson(request: Request): Promise<unknown> {
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    throw new AppError(400, "BAD_REQUEST", "Request body is too large.");
  }

  const text = await request.text();
  if (Buffer.byteLength(text, "utf8") > MAX_BODY_BYTES) {
    throw new AppError(400, "BAD_REQUEST", "Request body is too large.");
  }

  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new AppError(400, "BAD_REQUEST", "Request body must be valid JSON.");
  }
}

export default {
  async fetch(request: Request): Promise<Response> {
    const requestId = randomUUID();

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: responseHeaders(request) });
    }
    if (request.method !== "POST") {
      return json(
        request,
        { error: { code: "METHOD_NOT_ALLOWED", requestId } },
        405,
        { Allow: "POST, OPTIONS" },
      );
    }

    try {
      const ingestSecret = process.env.COOKIE_INGEST_SECRET;
      if (!ingestSecret || ingestSecret.length < 32) {
        throw new AppError(
          500,
          "CONFIGURATION_ERROR",
          "Required server environment variables are missing or invalid.",
        );
      }

      const authorization = request.headers.get("authorization") ?? undefined;
      const hasPermanentCredential = hasValidBearerToken(authorization, ingestSecret);
      const suppliedToken = bearerToken(authorization);
      if (!hasPermanentCredential && !suppliedToken) {
        throw new AppError(401, "UNAUTHORIZED", "Invalid bearer token.");
      }

      const apiKey = process.env.BROWSERBASE_API_KEY;
      if (!apiKey) {
        throw new AppError(
          500,
          "CONFIGURATION_ERROR",
          "Required server environment variables are missing or invalid.",
        );
      }

      const contentType = request.headers.get("content-type")?.split(";", 1)[0]?.trim();
      if (contentType !== "application/json") {
        throw new AppError(400, "BAD_REQUEST", "Content-Type must be application/json.");
      }

      const body = await readJson(request);
      const payload = parseCookiePayload(body, process.env.COOKIE_DOMAIN_ALLOWLIST);
      let transferGrant: TransferGrant | undefined;
      if (!hasPermanentCredential) {
        transferGrant = verifyTransferToken(suppliedToken!, payload.sessionId);
      }
      const result = await injectCookies(
        payload.sessionId,
        payload.cookies,
        apiKey,
        transferGrant ? "https://news.ycombinator.com/" : undefined,
      );
      if (transferGrant) consumeTransferToken(transferGrant);

      return json(request, {
        ok: true,
        requestId,
        sessionId: payload.sessionId,
        injected: result.injected,
        navigatedTo: transferGrant ? "https://news.ycombinator.com/" : undefined,
        cookies: result.cookies,
      }, 200);
    } catch (error) {
      const appError = error instanceof AppError
        ? error
        : new AppError(500, "CONFIGURATION_ERROR", "Unexpected server error.");

      return json(request, {
        ok: false,
        error: {
          code: appError.code,
          message: appError.message,
          ...(appError.details === undefined ? {} : { details: appError.details }),
          requestId,
        },
      }, appError.status);
    }
  },
};
