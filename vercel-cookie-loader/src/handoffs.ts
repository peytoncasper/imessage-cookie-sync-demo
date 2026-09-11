import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from "node:crypto";

import { AppError } from "./errors.js";

const HANDOFF_TTL_SECONDS = 15 * 60;
const TEXT_RATE_WINDOW_SECONDS = 60 * 60;
const TEXTS_PER_RECIPIENT_PER_WINDOW = 3;
const TOKEN_VERSION = "v1";
const IV_BYTES = 12;
const AUTH_TAG_BYTES = 16;

export interface Handoff {
  targetUrl: string;
  createdAt: string;
  expiresAt: string;
}

interface TokenPayload {
  u: string;
  c: number;
  e: number;
  n: string;
}

interface RateLimitEntry {
  count: number;
  resetAt: number;
}

// Vercel can reuse an instance, so these maps provide best-effort replay and
// rate-limit protection. Correct token validation does not depend on them.
const usedTokens = new Map<string, number>();
const recipientLimits = new Map<string, RateLimitEntry>();

function invalidHandoff(): AppError {
  return new AppError(404, "HANDOFF_NOT_FOUND", "This link is invalid or has expired.");
}

function encryptionKey(): Buffer {
  const secret = process.env.HANDOFF_SECRET?.trim();
  if (!secret || secret.length < 32) {
    throw new AppError(
      500,
      "CONFIGURATION_ERROR",
      "HANDOFF_SECRET must contain at least 32 characters.",
    );
  }
  return createHash("sha256").update(secret, "utf8").digest();
}

function pruneExpiredEntries(now: number): void {
  for (const [digest, expiresAt] of usedTokens) {
    if (expiresAt <= now) usedTokens.delete(digest);
  }
  for (const [recipient, entry] of recipientLimits) {
    if (entry.resetAt <= now) recipientLimits.delete(recipient);
  }
}

function tokenDigest(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

function parseToken(token: string): TokenPayload {
  if (!/^v1\.[A-Za-z0-9_-]{40,8192}$/.test(token)) throw invalidHandoff();

  try {
    const encoded = token.slice(TOKEN_VERSION.length + 1);
    const encrypted = Buffer.from(encoded, "base64url");
    if (encrypted.toString("base64url") !== encoded) throw invalidHandoff();
    if (encrypted.length <= IV_BYTES + AUTH_TAG_BYTES) throw invalidHandoff();

    const iv = encrypted.subarray(0, IV_BYTES);
    const authTag = encrypted.subarray(IV_BYTES, IV_BYTES + AUTH_TAG_BYTES);
    const ciphertext = encrypted.subarray(IV_BYTES + AUTH_TAG_BYTES);
    const decipher = createDecipheriv("aes-256-gcm", encryptionKey(), iv);
    decipher.setAAD(Buffer.from(TOKEN_VERSION, "utf8"));
    decipher.setAuthTag(authTag);
    const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    const payload = JSON.parse(plaintext.toString("utf8")) as Partial<TokenPayload>;

    if (
      typeof payload.u !== "string"
      || typeof payload.c !== "number"
      || typeof payload.e !== "number"
      || typeof payload.n !== "string"
      || !Number.isSafeInteger(payload.c)
      || !Number.isSafeInteger(payload.e)
      || payload.e <= payload.c
      || payload.e - payload.c !== HANDOFF_TTL_SECONDS * 1_000
      || !/^[A-Za-z0-9_-]{16}$/.test(payload.n)
    ) {
      throw invalidHandoff();
    }

    return payload as TokenPayload;
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw invalidHandoff();
  }
}

export async function createHandoff(targetUrl: string): Promise<{ id: string; handoff: Handoff }> {
  const createdAt = Date.now();
  const expiresAt = createdAt + HANDOFF_TTL_SECONDS * 1_000;
  const payload: TokenPayload = {
    u: targetUrl,
    c: createdAt,
    e: expiresAt,
    n: randomBytes(12).toString("base64url"),
  };
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(), iv);
  cipher.setAAD(Buffer.from(TOKEN_VERSION, "utf8"));
  const ciphertext = Buffer.concat([
    cipher.update(JSON.stringify(payload), "utf8"),
    cipher.final(),
  ]);
  const id = `${TOKEN_VERSION}.${Buffer.concat([iv, cipher.getAuthTag(), ciphertext]).toString("base64url")}`;

  return {
    id,
    handoff: {
      targetUrl,
      createdAt: new Date(createdAt).toISOString(),
      expiresAt: new Date(expiresAt).toISOString(),
    },
  };
}

export async function redeemHandoff(id: string): Promise<Handoff> {
  const now = Date.now();
  pruneExpiredEntries(now);
  const digest = tokenDigest(id);
  if (usedTokens.has(digest)) throw invalidHandoff();

  const payload = parseToken(id);
  if (payload.e <= now) throw invalidHandoff();

  usedTokens.set(digest, payload.e);
  return {
    targetUrl: payload.u,
    createdAt: new Date(payload.c).toISOString(),
    expiresAt: new Date(payload.e).toISOString(),
  };
}

export async function deleteHandoff(id: string): Promise<void> {
  usedTokens.set(tokenDigest(id), Date.now() + HANDOFF_TTL_SECONDS * 1_000);
}

export async function enforceRecipientRateLimit(phoneNumber: string): Promise<void> {
  const now = Date.now();
  pruneExpiredEntries(now);
  const digest = createHash("sha256").update(phoneNumber).digest("hex");
  const current = recipientLimits.get(digest);
  const entry = !current || current.resetAt <= now
    ? { count: 1, resetAt: now + TEXT_RATE_WINDOW_SECONDS * 1_000 }
    : { ...current, count: current.count + 1 };

  recipientLimits.set(digest, entry);
  if (entry.count > TEXTS_PER_RECIPIENT_PER_WINDOW) {
    throw new AppError(429, "RATE_LIMITED", "Too many texts were requested for this recipient.");
  }
}
