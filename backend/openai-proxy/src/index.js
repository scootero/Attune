/**
 * Attune OpenAI proxy — keeps the OpenAI API key on the server.
 *
 * App sends:  Authorization: Bearer <APP_PROXY_TOKEN>
 * Worker adds: Authorization: Bearer <OPENAI_API_KEY>
 * and forwards the body to OpenAI Chat Completions unchanged.
 */

export default {
  async fetch(request, env) {
    // Only allow POST /v1/chat/completions (same path the iOS client uses).
    const url = new URL(request.url);
    if (request.method === "OPTIONS") {
      return corsResponse(null, 204);
    }
    if (request.method !== "POST" || url.pathname !== "/v1/chat/completions") {
      return corsResponse(JSON.stringify({ error: "Not found" }), 404, {
        "Content-Type": "application/json",
      });
    }

    // Require the app proxy token so random callers cannot burn your OpenAI quota.
    const auth = request.headers.get("Authorization") || "";
    const expected = `Bearer ${env.APP_PROXY_TOKEN}`;
    if (!env.APP_PROXY_TOKEN || auth !== expected) {
      return corsResponse(JSON.stringify({ error: "Unauthorized" }), 401, {
        "Content-Type": "application/json",
      });
    }

    if (!env.OPENAI_API_KEY) {
      return corsResponse(JSON.stringify({ error: "Server misconfigured" }), 500, {
        "Content-Type": "application/json",
      });
    }

    // Forward the request body as-is so Structured Outputs keep working.
    const body = await request.arrayBuffer();
    const openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body,
    });

    const responseBody = await openaiResponse.arrayBuffer();
    return corsResponse(responseBody, openaiResponse.status, {
      "Content-Type": openaiResponse.headers.get("Content-Type") || "application/json",
    });
  },
};

/** Attach CORS headers so local testing from a browser is possible if needed. */
function corsResponse(body, status, headers = {}) {
  return new Response(body, {
    status,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      ...headers,
    },
  });
}
