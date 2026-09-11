import {
  createHash,
  createHmac,
  randomBytes,
  timingSafeEqual,
} from "node:crypto";

import { AppError } from "./errors.js";

const TOKEN_VERSION = "ct1";
const TOKEN_TTL_MS = 10 * 60 * 1_000;

interface TransferTokenPayload {
  s: string;
  i: number;
  e: number;
  n: string;
}

export interface TransferGrant {
  digest: string;
  expiresAt: number;
}

const usedTokens = new Map<string, number>();

function tokenKey(): string {
  const secret = process.env.COOKIE_INGEST_SECRET?.trim();
  if (!secret || secret.length < 32) {
    throw new AppError(
      500,
      "CONFIGURATION_ERROR",
      "Required server environment variables are missing or invalid.",
    );
  }
  return secret;
}

function unauthorized(): AppError {
  return new AppError(401, "UNAUTHORIZED", "Invalid or expired transfer token.");
}

function signature(encodedPayload: string): Buffer {
  return createHmac("sha256", tokenKey())
    .update(`${TOKEN_VERSION}.${encodedPayload}`, "utf8")
    .digest();
}

function pruneUsedTokens(now: number): void {
  for (const [digest, expiresAt] of usedTokens) {
    if (expiresAt <= now) usedTokens.delete(digest);
  }
}

export function createTransferToken(sessionId: string): { token: string; expiresAt: string } {
  const issuedAt = Date.now();
  const expiresAt = issuedAt + TOKEN_TTL_MS;
  const payload: TransferTokenPayload = {
    s: sessionId,
    i: issuedAt,
    e: expiresAt,
    n: randomBytes(12).toString("base64url"),
  };
  const encodedPayload = Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
  const encodedSignature = signature(encodedPayload).toString("base64url");
  return {
    token: `${TOKEN_VERSION}.${encodedPayload}.${encodedSignature}`,
    expiresAt: new Date(expiresAt).toISOString(),
  };
}

export function verifyTransferToken(token: string, expectedSessionId: string): TransferGrant {
  if (!/^ct1\.[A-Za-z0-9_-]{40,1024}\.[A-Za-z0-9_-]{43}$/.test(token)) {
    throw unauthorized();
  }

  try {
    const [, encodedPayload, encodedSignature] = token.split(".");
    if (!encodedPayload || !encodedSignature) throw unauthorized();

    const suppliedSignature = Buffer.from(encodedSignature, "base64url");
    const expectedSignature = signature(encodedPayload);
    if (
      suppliedSignature.length !== expectedSignature.length
      || !timingSafeEqual(suppliedSignature, expectedSignature)
    ) {
      throw unauthorized();
    }

    const payloadBuffer = Buffer.from(encodedPayload, "base64url");
    if (payloadBuffer.toString("base64url") !== encodedPayload) throw unauthorized();
    const payload = JSON.parse(payloadBuffer.toString("utf8")) as Partial<TransferTokenPayload>;
    const now = Date.now();
    if (
      payload.s !== expectedSessionId
      || typeof payload.i !== "number"
      || typeof payload.e !== "number"
      || typeof payload.n !== "string"
      || !Number.isSafeInteger(payload.i)
      || !Number.isSafeInteger(payload.e)
      || payload.e - payload.i !== TOKEN_TTL_MS
      || payload.i > now + 5_000
      || payload.e <= now
      || !/^[A-Za-z0-9_-]{16}$/.test(payload.n)
    ) {
      throw unauthorized();
    }

    pruneUsedTokens(now);
    const digest = createHash("sha256").update(token, "utf8").digest("hex");
    if (usedTokens.has(digest)) throw unauthorized();
    return { digest, expiresAt: payload.e };
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw unauthorized();
  }
}

export function consumeTransferToken(grant: TransferGrant): void {
  usedTokens.set(grant.digest, grant.expiresAt);
}
