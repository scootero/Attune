import { describe, expect, it, vi } from "vitest";
import { handleRequest } from "../src/handler";

const env = {
  APP_PROXY_TOKEN: "test-proxy-token",
  OPENAI_API_KEY: "test-openai-key",
};

function validBody(schemaName = "checkin_extraction") {
  return {
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: "Extract an update." },
      { role: "user", content: "I walked 2,000 steps." },
    ],
    response_format: {
      type: "json_schema",
      json_schema: {
        name: schemaName,
        strict: true,
        schema: { type: "object" },
      },
    },
  };
}

function request(body: unknown = validBody(), headers: Record<string, string> = {}) {
  return new Request("https://attune.example/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.APP_PROXY_TOKEN}`,
      "Content-Type": "application/json",
      ...headers,
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

describe("Attune OpenAI gateway", () => {
  it.each(["checkin_extraction", "intentions_parse", "items_extraction"])(
    "accepts the existing %s request shape and preserves the upstream response",
    async (schemaName) => {
      const upstreamBody = JSON.stringify({ choices: [{ message: { content: "{}" } }] });
      let forwardedInit: RequestInit | undefined;
      const upstreamFetch = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
        forwardedInit = init;
        return new Response(upstreamBody, {
          status: 200,
          headers: { "Content-Type": "application/json", "x-request-id": "openai-test" },
        });
      });

      const response = await handleRequest(request(validBody(schemaName)), env, upstreamFetch);

      expect(response.status).toBe(200);
      expect(await response.text()).toBe(upstreamBody);
      expect(response.headers.get("X-Attune-Request-Id")).toBeTruthy();
      expect(upstreamFetch).toHaveBeenCalledOnce();

      const forwarded = JSON.parse(String(forwardedInit?.body));
      expect(forwarded.store).toBe(false);
      expect(forwarded.model).toBe("gpt-4o-mini");
      expect(forwarded.response_format.json_schema.name).toBe(schemaName);
    },
  );

  it("passes through an OpenAI error status and body", async () => {
    const upstreamBody = JSON.stringify({ error: { code: "credit_balance_exhausted" } });
    const upstreamFetch = vi.fn(async () =>
      new Response(upstreamBody, { status: 429, headers: { "Content-Type": "application/json" } }),
    );

    const response = await handleRequest(request(), env, upstreamFetch);

    expect(response.status).toBe(429);
    expect(await response.text()).toBe(upstreamBody);
  });

  it("rejects an invalid proxy token without contacting OpenAI", async () => {
    const upstreamFetch = vi.fn();
    const response = await handleRequest(
      request(validBody(), { Authorization: "Bearer wrong-token" }),
      env,
      upstreamFetch,
    );

    expect(response.status).toBe(401);
    expect(upstreamFetch).not.toHaveBeenCalled();
  });

  it.each([
    ["model", { ...validBody(), model: "gpt-4o" }],
    ["schema", validBody("unknown_schema")],
    ["streaming", { ...validBody(), stream: true }],
  ])("rejects unsupported %s requests", async (_label, body) => {
    const upstreamFetch = vi.fn();
    const response = await handleRequest(request(body), env, upstreamFetch);

    expect(response.status).toBe(400);
    expect(upstreamFetch).not.toHaveBeenCalled();
  });

  it("rejects malformed JSON", async () => {
    const response = await handleRequest(request("{"), env, vi.fn());
    expect(response.status).toBe(400);
  });

  it("rejects an oversized request before calling OpenAI", async () => {
    const oversized = validBody();
    oversized.messages[1].content = "x".repeat(270_000);
    const upstreamFetch = vi.fn();
    const response = await handleRequest(request(oversized), env, upstreamFetch);

    expect(response.status).toBe(413);
    expect(upstreamFetch).not.toHaveBeenCalled();
  });

  it("supports an emergency kill switch", async () => {
    const upstreamFetch = vi.fn();
    const response = await handleRequest(
      request(),
      { ...env, AI_ENABLED: "false" },
      upstreamFetch,
    );

    expect(response.status).toBe(503);
    expect(upstreamFetch).not.toHaveBeenCalled();
  });

  it("maps an upstream network failure to a safe 502 response", async () => {
    const response = await handleRequest(request(), env, async () => {
      throw new Error("network details must not reach the client");
    });

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "AI provider unavailable" });
  });
});
