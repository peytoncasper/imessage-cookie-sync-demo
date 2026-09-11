import { AppError } from "./errors.js";
import { hasValidBearerToken } from "./auth.js";

const MAX_BODY_BYTES = 64 * 1024;

export function jsonResponse(
  body: unknown,
  status = 200,
  extraHeaders?: HeadersInit,
): Response {
  const headers = new Headers({
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8",
    "X-Content-Type-Options": "nosniff",
  });
  if (extraHeaders) {
    new Headers(extraHeaders).forEach((value, key) => headers.set(key, value));
  }
  return new Response(JSON.stringify(body), { status, headers });
}

export async function readJson(request: Request): Promise<unknown> {
  if (request.headers.get("content-type")?.split(";", 1)[0]?.trim() !== "application/json") {
    throw new AppError(400, "BAD_REQUEST", "Content-Type must be application/json.");
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

export function requireBearer(request: Request, environmentName: string): void {
  const secret = process.env[environmentName];
  if (!secret || secret.length < 32) {
    throw new AppError(500, "CONFIGURATION_ERROR", `${environmentName} is missing or too short.`);
  }
  if (!hasValidBearerToken(request.headers.get("authorization") ?? undefined, secret)) {
    throw new AppError(401, "UNAUTHORIZED", "Invalid bearer token.");
  }
}

export function errorResponse(error: unknown, requestId: string): Response {
  const appError = error instanceof AppError
    ? error
    : new AppError(500, "CONFIGURATION_ERROR", "Unexpected server error.");
  return jsonResponse({
    ok: false,
    error: {
      code: appError.code,
      message: appError.message,
      ...(appError.details === undefined ? {} : { details: appError.details }),
      requestId,
    },
  }, appError.status);
}
