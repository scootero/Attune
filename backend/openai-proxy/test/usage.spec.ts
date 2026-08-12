import { env as cloudflareEnv } from "cloudflare:test";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { GatewayEnv } from "../src/env";
import { handleRequest } from "../src/handler";
import { INSTALLATION_ID_HEADER, USAGE_PATH } from "../src/usage";

const installationId = "82F94C18-39DA-4DA4-A8CA-89C9DD0D1AA1";

function gatewayEnv(overrides: Partial<GatewayEnv> = {}): GatewayEnv {
  return {
    USAGE_DB: cloudflareEnv.USAGE_DB,
    APP_PROXY_TOKEN: "test-proxy-token",
    OPENAI_API_KEY: "test-openai-key",
    USAGE_LIMIT_MODE: "enforced",
    MONTHLY_AI_UNIT_LIMIT: "1000",
    MONTHLY_AI_WARNING_FRACTION: "0.8",
    ...overrides,
  };
}

function usageRequest(includeInstallationId = true): Request {
  const headers: Record<string, string> = {
    Authorization: "Bearer test-proxy-token",
  };
  if (includeInstallationId) headers[INSTALLATION_ID_HEADER] = installationId;
  return new Request(`https://attune.example${USAGE_PATH}`, { headers });
}

function legacyRequest(): Request {
  return new Request("https://attune.example/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: "Bearer test-proxy-token",
      "Content-Type": "application/json",
      [INSTALLATION_ID_HEADER]: installationId,
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [{ role: "user", content: "A short test." }],
      response_format: {
        type: "json_schema",
        json_schema: { name: "intentions_parse", strict: true, schema: { type: "object" } },
      },
    }),
  });
}

function openAIResponse(promptTokens: number, completionTokens: number): Response {
  return Response.json({
    choices: [{ message: { content: "{}" } }],
    usage: { prompt_tokens: promptTokens, completion_tokens: completionTokens },
  });
}

beforeEach(async () => {
  await cloudflareEnv.USAGE_DB.prepare(`
    CREATE TABLE IF NOT EXISTS ai_monthly_usage (
      installation_hash TEXT NOT NULL,
      period_key TEXT NOT NULL,
      units INTEGER NOT NULL DEFAULT 0 CHECK (units >= 0),
      request_count INTEGER NOT NULL DEFAULT 0 CHECK (request_count >= 0),
      updated_at TEXT NOT NULL,
      PRIMARY KEY (installation_hash, period_key)
    ) WITHOUT ROWID;
  `).run();
  await cloudflareEnv.USAGE_DB.prepare("DELETE FROM ai_monthly_usage").run();
});

describe("monthly AI usage enforcement", () => {
  it("requires an anonymous installation identifier when enforcement is active", async () => {
    const response = await handleRequest(usageRequest(false), gatewayEnv(), vi.fn());
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ code: "installation_id_required" });
  });

  it("returns a calendar-month reset and no personal content", async () => {
    const response = await handleRequest(usageRequest(), gatewayEnv(), vi.fn());
    expect(response.status).toBe(200);
    const body = await response.json() as Record<string, unknown>;
    expect(body).toMatchObject({ usedUnits: 0, limitUnits: 1000, warningAtUnits: 800 });
    expect(String(body.resetsAt)).toMatch(/T00:00:00\.000Z$/);
    expect(JSON.stringify(body)).not.toContain(installationId);
  });

  it("reconciles a successful call to actual weighted token usage", async () => {
    const response = await handleRequest(
      legacyRequest(),
      gatewayEnv({ MONTHLY_AI_UNIT_LIMIT: "100000" }),
      async () => openAIResponse(100, 50),
    );
    expect(response.status).toBe(200);
    expect(response.headers.get("X-Attune-Usage-Used")).toBe("300");

    const status = await handleRequest(
      usageRequest(),
      gatewayEnv({ MONTHLY_AI_UNIT_LIMIT: "100000" }),
      vi.fn(),
    );
    expect(await status.json()).toMatchObject({ usedUnits: 300 });
  });

  it("rolls back a reservation when OpenAI fails", async () => {
    const response = await handleRequest(
      legacyRequest(),
      gatewayEnv({ MONTHLY_AI_UNIT_LIMIT: "100000" }),
      async () => Response.json({ error: "provider failed" }, { status: 500 }),
    );
    expect(response.status).toBe(500);
    const status = await handleRequest(
      usageRequest(),
      gatewayEnv({ MONTHLY_AI_UNIT_LIMIT: "100000" }),
      vi.fn(),
    );
    expect(await status.json()).toMatchObject({ usedUnits: 0 });
  });

  it("blocks before OpenAI when the next request would exceed the allowance", async () => {
    const upstream = vi.fn(async () => openAIResponse(10, 10));
    const response = await handleRequest(legacyRequest(), gatewayEnv(), upstream);
    expect(response.status).toBe(429);
    expect(await response.json()).toMatchObject({
      code: "monthly_ai_limit_reached",
      limitUnits: 1000,
      limited: true,
    });
    expect(upstream).not.toHaveBeenCalled();
  });

  it("keeps older builds working in shadow mode", async () => {
    const request = legacyRequest();
    request.headers.delete(INSTALLATION_ID_HEADER);
    const upstream = vi.fn(async () => openAIResponse(10, 10));
    const response = await handleRequest(
      request,
      gatewayEnv({ USAGE_LIMIT_MODE: "shadow" }),
      upstream,
    );
    expect(response.status).toBe(200);
    expect(upstream).toHaveBeenCalledOnce();
  });
});
