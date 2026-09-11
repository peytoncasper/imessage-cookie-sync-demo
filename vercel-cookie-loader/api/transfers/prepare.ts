import { randomUUID } from "node:crypto";

import { createBrowserbaseSession } from "../../src/browserbase.js";
import { AppError } from "../../src/errors.js";
import { errorResponse, jsonResponse, requireBearer } from "../../src/http.js";
import { createTransferToken } from "../../src/transferTokens.js";

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

    try {
      requireBearer(request, "APP_TRANSFER_SECRET");
      const apiKey = process.env.BROWSERBASE_API_KEY;
      if (!apiKey) {
        throw new AppError(
          500,
          "CONFIGURATION_ERROR",
          "Required server environment variables are missing or invalid.",
        );
      }

      const session = await createBrowserbaseSession(apiKey);
      const transfer = createTransferToken(session.id);
      return jsonResponse({
        ok: true,
        requestId,
        sessionId: session.id,
        inspectorUrl: session.inspectorUrl,
        token: transfer.token,
        tokenExpiresAt: transfer.expiresAt,
        sessionExpiresAt: session.expiresAt,
      }, 201);
    } catch (error) {
      return errorResponse(error, requestId);
    }
  },
};
