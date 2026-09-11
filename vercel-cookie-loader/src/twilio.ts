import { AppError } from "./errors.js";

export interface TwilioResult {
  sid: string;
  status: string;
}

interface TwilioResponse {
  sid?: unknown;
  status?: unknown;
}

interface TextbeltResponse {
  success?: unknown;
  textId?: unknown;
  error?: unknown;
}

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new AppError(500, "CONFIGURATION_ERROR", `${name} is missing.`);
  return value;
}

export function parsePhoneNumber(input: unknown): string {
  if (typeof input !== "string" || !/^\+[1-9][0-9]{7,14}$/.test(input)) {
    throw new AppError(400, "BAD_REQUEST", "to must be an E.164 phone number.");
  }
  return input;
}

export async function sendText(to: string, body: string): Promise<TwilioResult> {
  if (process.env.SMS_PROVIDER?.trim().toLowerCase() === "textbelt") {
    return sendWithTextbelt(to, body);
  }

  const accountSid = required("TWILIO_ACCOUNT_SID");
  const messagingServiceSid = required("TWILIO_MESSAGING_SERVICE_SID");
  const apiKeySid = process.env.TWILIO_API_KEY_SID;
  const apiKeySecret = process.env.TWILIO_API_KEY_SECRET;
  const authToken = process.env.TWILIO_AUTH_TOKEN;

  if (!/^AC[0-9a-fA-F]{32}$/.test(accountSid)) {
    throw new AppError(500, "CONFIGURATION_ERROR", "Twilio credentials are malformed.");
  }
  const usesAPIKey = Boolean(apiKeySid && apiKeySecret);
  if (usesAPIKey && !/^SK[0-9a-fA-F]{32}$/.test(apiKeySid!)) {
    throw new AppError(500, "CONFIGURATION_ERROR", "Twilio API key SID is malformed.");
  }
  if (!usesAPIKey && !authToken) {
    throw new AppError(
      500,
      "CONFIGURATION_ERROR",
      "Configure a Twilio API key pair or TWILIO_AUTH_TOKEN.",
    );
  }
  if (!/^MG[0-9a-fA-F]{32}$/.test(messagingServiceSid)) {
    throw new AppError(500, "CONFIGURATION_ERROR", "TWILIO_MESSAGING_SERVICE_SID is malformed.");
  }

  const form = new URLSearchParams({
    To: to,
    MessagingServiceSid: messagingServiceSid,
    Body: body,
  });

  let response: Response;
  const username = usesAPIKey ? apiKeySid! : accountSid;
  const password = usesAPIKey ? apiKeySecret! : authToken!;
  try {
    response = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`,
      {
        method: "POST",
        headers: {
          Authorization: `Basic ${Buffer.from(`${username}:${password}`).toString("base64")}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: form,
        signal: AbortSignal.timeout(8_000),
      },
    );
  } catch {
    throw new AppError(502, "SMS_PROVIDER_ERROR", "The SMS provider could not be reached.");
  }

  const payload = await response.json().catch(() => ({})) as TwilioResponse;
  if (!response.ok || typeof payload.sid !== "string" || typeof payload.status !== "string") {
    throw new AppError(502, "SMS_PROVIDER_ERROR", "The SMS provider rejected the message.");
  }

  return { sid: payload.sid, status: payload.status };
}

async function sendWithTextbelt(to: string, body: string): Promise<TwilioResult> {
  const key = process.env.TEXTBELT_API_KEY?.trim() || "textbelt";
  const configuredBrand = process.env.SMS_BRAND_NAME?.trim();
  const sender = configuredBrand && configuredBrand.length <= 40
    ? configuredBrand
    : "Cookie Clip";
  const form = new URLSearchParams({
    phone: to,
    message: body,
    key,
    sender,
  });

  let response: Response;
  try {
    response = await fetch("https://textbelt.com/text", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
      signal: AbortSignal.timeout(8_000),
    });
  } catch {
    throw new AppError(502, "SMS_PROVIDER_ERROR", "The SMS provider could not be reached.");
  }

  const payload = await response.json().catch(() => ({})) as TextbeltResponse;
  if (!response.ok || payload.success !== true || !["string", "number"].includes(typeof payload.textId)) {
    const detail = typeof payload.error === "string" ? payload.error : undefined;
    throw new AppError(502, "SMS_PROVIDER_ERROR", "The SMS provider rejected the message.", detail);
  }

  return { sid: `textbelt:${String(payload.textId)}`, status: "accepted" };
}
