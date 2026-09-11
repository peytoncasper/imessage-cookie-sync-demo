import { randomUUID } from "node:crypto";

import { redeemHandoff } from "../../src/handoffs.js";
import { errorResponse, jsonResponse, readJson } from "../../src/http.js";

interface RedeemRequest {
  id?: unknown;
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

    try {
      const body = await readJson(request) as RedeemRequest;
      const handoff = await redeemHandoff(typeof body.id === "string" ? body.id : "");
      return jsonResponse({
        ok: true,
        requestId,
        targetUrl: handoff.targetUrl,
      });
    } catch (error) {
      return errorResponse(error, requestId);
    }
  },
};
