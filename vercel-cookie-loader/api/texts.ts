import { randomUUID } from "node:crypto";

import { AppError } from "../src/errors.js";
import {
  createHandoff,
  deleteHandoff,
  enforceRecipientRateLimit,
} from "../src/handoffs.js";
import {
  errorResponse,
  jsonResponse,
  readJson,
  requireBearer,
} from "../src/http.js";
import { parseTargetURL, publicBaseURL } from "../src/targets.js";
import { parsePhoneNumber, sendText } from "../src/twilio.js";

interface TextRequest {
  to?: unknown;
  targetUrl?: unknown;
  consentConfirmed?: unknown;
}

export default {
  async fetch(request: Request): Promise<Response> {
    const requestId = randomUUID();
    if (request.method !== "POST") {
      return jsonResponse(
        { ok: false, error: { code: "METHOD_NOT_ALLOWED", requestId } },
        405,
        { Allow: "POST" },
      );
    }

    let handoffId: string | undefined;
    try {
      requireBearer(request, "TEXT_SEND_SECRET");
      const body = await readJson(request) as TextRequest;
      if (body.consentConfirmed !== true) {
        throw new AppError(
          400,
          "BAD_REQUEST",
          "consentConfirmed must be true before an automated text can be sent.",
        );
      }

      const to = parsePhoneNumber(body.to);
      const targetUrl = parseTargetURL(body.targetUrl, process.env.TARGET_DOMAIN_ALLOWLIST);
      const baseURL = publicBaseURL(process.env.PUBLIC_BASE_URL);

      await enforceRecipientRateLimit(to);
      const created = await createHandoff(targetUrl);
      handoffId = created.id;

      const link = new URL("/open", baseURL);
      link.searchParams.set("h", created.id);

      const configuredBrand = process.env.SMS_BRAND_NAME?.trim();
      const brand = configuredBrand && configuredBrand.length <= 40
        ? configuredBrand
        : "Cookie Clip";
      const message = `${brand}: Open your requested secure link: ${link.toString()} Reply STOP to opt out.`;
      const twilio = await sendText(to, message);

      return jsonResponse({
        ok: true,
        requestId,
        messageSid: twilio.sid,
        status: twilio.status,
        link: link.toString(),
        expiresAt: created.handoff.expiresAt,
      }, 202);
    } catch (error) {
      if (handoffId) await deleteHandoff(handoffId).catch(() => undefined);
      return errorResponse(error, requestId);
    }
  },
};
