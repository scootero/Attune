/**
 * Backward-compatible Attune OpenAI gateway.
 *
 * The current iOS app still sends the complete Chat Completions request. This
 * phase validates that request against the three shapes Attune already uses.
 * A later version will move prompts and schemas entirely into this Worker.
 */

import { buildTask, isTaskPath, type BuiltTask } from "./tasks";
import { suggestionAction } from "./intention-suggestion-actions";

interface Env {
  APP_PROXY_TOKEN?: string;
  OPENAI_API_KEY?: string;
  /** Set to the literal string "false" to stop AI requests without an app update. */
  AI_ENABLED?: string;
}

type UpstreamFetch = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

type ChatRequest = {
  model: string;
  messages: Array<{ role: "system" | "user"; content: string }>;
  response_format: {
    type: "json_schema";
    json_schema: {
      name: string;
      strict: boolean;
      schema: Record<string, unknown>;
    };
  };
  store?: boolean;
};

const ENDPOINT = "/v1/chat/completions";
const OPENAI_URL = "https://api.openai.com/v1/chat/completions";
const MAX_BODY_BYTES = 256 * 1024;
const MAX_MESSAGE_CHARACTERS = 200_000;
const UPSTREAM_TIMEOUT_MS = 45_000;
const ALLOWED_MODEL = "gpt-4o-mini";
const ALLOWED_SCHEMA_NAMES = new Set([
  "checkin_extraction",
  "intentions_parse",
  "items_extraction",
]);
const ALLOWED_TOP_LEVEL_KEYS = new Set([
  "model",
  "messages",
  "response_format",
  "store",
]);

/** Exported for local Worker-runtime tests; production uses the default handler. */
export async function handleRequest(
  request: Request,
  env: Env,
  upstreamFetch: UpstreamFetch,
): Promise<Response> {
  const startedAt = Date.now();
  const requestId = crypto.randomUUID();
  const url = new URL(request.url);
  const pathname = url.pathname;

  if (request.method === "OPTIONS") {
    return corsResponse(null, 204, requestId);
  }

  const isLegacyEndpoint = pathname === ENDPOINT;
  const isServerOwnedTask = isTaskPath(pathname);
  if (request.method !== "POST" || (!isLegacyEndpoint && !isServerOwnedTask)) {
    return jsonError("Not found", 404, requestId);
  }

  if (env.AI_ENABLED?.toLowerCase() === "false") {
    return jsonError("AI processing is temporarily unavailable", 503, requestId);
  }

  if (!env.APP_PROXY_TOKEN || !(await hasValidAuthorization(request, env.APP_PROXY_TOKEN))) {
    return jsonError("Unauthorized", 401, requestId);
  }

  if (!env.OPENAI_API_KEY) {
    console.error({ event: "gateway_misconfigured", requestId });
    return jsonError("Server misconfigured", 500, requestId);
  }

  const contentType = request.headers.get("Content-Type")?.toLowerCase() ?? "";
  if (!contentType.startsWith("application/json")) {
    return jsonError("Content-Type must be application/json", 415, requestId);
  }

  const declaredLength = Number(request.headers.get("Content-Length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    return jsonError("Request body is too large", 413, requestId);
  }

  let bodyBytes: ArrayBuffer;
  try {
    bodyBytes = await request.arrayBuffer();
  } catch {
    return jsonError("Could not read request body", 400, requestId);
  }
  if (bodyBytes.byteLength > MAX_BODY_BYTES) {
    return jsonError("Request body is too large", 413, requestId);
  }

  let rawBody: unknown;
  try {
    rawBody = JSON.parse(new TextDecoder().decode(bodyBytes));
  } catch {
    return jsonError("Request body must be valid JSON", 400, requestId);
  }

  if (isServerOwnedTask) {
    const task = buildTask(pathname, rawBody);
    if (!task.ok) return jsonError(task.error, 400, requestId);
    return performServerOwnedTask(task.value, env.OPENAI_API_KEY, upstreamFetch, requestId, startedAt);
  }

  const validation = validateChatRequest(rawBody);
  if (!validation.ok) {
    return jsonError(validation.error, 400, requestId);
  }

  const chatRequest = validation.value;
  // Attune never needs OpenAI request storage. Enforce this server-side even
  // while the legacy endpoint still accepts client-owned prompts and schemas.
  chatRequest.store = false;

  const messageCharacters = chatRequest.messages.reduce(
    (total, message) => total + message.content.length,
    0,
  );
  const schemaName = chatRequest.response_format.json_schema.name;

  try {
    const upstreamResponse = await upstreamFetch(OPENAI_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
        "X-Client-Request-Id": requestId,
      },
      body: JSON.stringify(chatRequest),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });

    const responseBody = await upstreamResponse.arrayBuffer();
    const openAIRequestId = upstreamResponse.headers.get("x-request-id") ?? undefined;
    console.log({
      event: "gateway_request",
      requestId,
      openAIRequestId,
      model: chatRequest.model,
      schemaName,
      messageCharacters,
      status: upstreamResponse.status,
      elapsedMs: Date.now() - startedAt,
    });

    return corsResponse(responseBody, upstreamResponse.status, requestId, {
      "Content-Type":
        upstreamResponse.headers.get("Content-Type") ?? "application/json",
    });
  } catch (error) {
    const timedOut = error instanceof DOMException && error.name === "TimeoutError";
    console.error({
      event: "gateway_upstream_failure",
      requestId,
      model: chatRequest.model,
      schemaName,
      messageCharacters,
      timedOut,
      elapsedMs: Date.now() - startedAt,
    });
    return jsonError(
      timedOut ? "AI provider timed out" : "AI provider unavailable",
      timedOut ? 504 : 502,
      requestId,
    );
  }
}

async function performServerOwnedTask(
  task: BuiltTask,
  openAIAPIKey: string,
  upstreamFetch: UpstreamFetch,
  requestId: string,
  startedAt: number,
): Promise<Response> {
  try {
    const upstreamResponse = await upstreamFetch(OPENAI_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIAPIKey}`,
        "Content-Type": "application/json",
        "X-Client-Request-Id": requestId,
      },
      body: JSON.stringify(task.request),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
    const responseBody = await upstreamResponse.arrayBuffer();
    const openAIRequestId = upstreamResponse.headers.get("x-request-id") ?? undefined;

    console.log({
      event: "gateway_task",
      requestId,
      openAIRequestId,
      taskName: task.taskName,
      model: task.request.model,
      schemaName: task.request.response_format.json_schema.name,
      inputCharacters: task.inputCharacters,
      status: upstreamResponse.status,
      elapsedMs: Date.now() - startedAt,
    });

    if (!upstreamResponse.ok) {
      return corsResponse(responseBody, upstreamResponse.status, requestId, {
        "Content-Type":
          upstreamResponse.headers.get("Content-Type") ?? "application/json",
        "X-Attune-Contract-Version": "1",
      });
    }

    const taskOutput = parseStructuredTaskOutput(responseBody, task);
    if (!taskOutput.ok) {
      console.error({
        event: "gateway_task_invalid_provider_response",
        requestId,
        openAIRequestId,
        taskName: task.taskName,
      });
      return jsonError("AI provider returned an invalid response", 502, requestId, {
        "X-Attune-Contract-Version": "1",
      });
    }

    return corsResponse(JSON.stringify(taskOutput.value), 200, requestId, {
      "Content-Type": "application/json",
      "X-Attune-Contract-Version": "1",
    });
  } catch (error) {
    const timedOut = error instanceof DOMException && error.name === "TimeoutError";
    console.error({
      event: "gateway_task_upstream_failure",
      requestId,
      taskName: task.taskName,
      timedOut,
      elapsedMs: Date.now() - startedAt,
    });
    return jsonError(
      timedOut ? "AI provider timed out" : "AI provider unavailable",
      timedOut ? 504 : 502,
      requestId,
      { "X-Attune-Contract-Version": "1" },
    );
  }
}

function parseStructuredTaskOutput(
  responseBody: ArrayBuffer,
  task: BuiltTask,
): { ok: true; value: Record<string, unknown> } | { ok: false } {
  try {
    const response = JSON.parse(new TextDecoder().decode(responseBody));
    if (response?.choices?.[0]?.finish_reason !== "stop") return { ok: false };
    const content = response?.choices?.[0]?.message?.content;
    if (typeof content !== "string") return { ok: false };
    const value = JSON.parse(content);
    if (!isRecord(value) || !hasExpectedTaskOutputShape(task.taskName, value)) return { ok: false };
    if (task.taskName !== "intention_suggestion") return { ok: true, value };
    if (value.actionId === null) return { ok: true, value: { suggestion: null } };
    if (typeof value.actionId !== "string" || typeof value.reason !== "string" || value.reason.length < 1 || value.reason.length > 140 || !Array.isArray(value.evidenceItemIds)) return { ok: false };
    const action = suggestionAction(value.actionId);
    const context = task.suggestionContext;
    const evidenceIds = value.evidenceItemIds;
    if (!action || !context || !context.allowedActionIds.includes(action.actionId) || context.declinedActionIds.includes(action.actionId) || evidenceIds.length < 1 || evidenceIds.some((id) => typeof id !== "string" || !context.evidenceItemIds.includes(id))) return { ok: false };
    return { ok: true, value: { suggestion: { ...action, reason: value.reason, evidenceItemIds: evidenceIds } } };
  } catch {
    return { ok: false };
  }
}

function hasExpectedTaskOutputShape(
  taskName: BuiltTask["taskName"],
  value: Record<string, unknown>,
): boolean {
  switch (taskName) {
    case "check_in":
      return (
        hasExactKeys(value, ["updates", "moodLabel", "moodScore"]) &&
        Array.isArray(value.updates) &&
        (value.moodLabel === null || typeof value.moodLabel === "string") &&
        (value.moodScore === null || typeof value.moodScore === "number")
      );
    case "intentions":
      return hasExactKeys(value, ["intentions"]) && Array.isArray(value.intentions);
    case "listening":
      return hasExactKeys(value, ["items"]) && Array.isArray(value.items);
    case "intention_suggestion":
      return hasExactKeys(value, ["actionId", "reason", "evidenceItemIds"]) &&
        (value.actionId === null || typeof value.actionId === "string") &&
        (value.reason === null || typeof value.reason === "string") &&
        Array.isArray(value.evidenceItemIds);
  }
}

function hasExactKeys(value: Record<string, unknown>, expectedKeys: string[]): boolean {
  const keys = Object.keys(value);
  return keys.length === expectedKeys.length && expectedKeys.every((key) => keys.includes(key));
}

async function hasValidAuthorization(request: Request, proxyToken: string): Promise<boolean> {
  const provided = new TextEncoder().encode(request.headers.get("Authorization") ?? "");
  const expected = new TextEncoder().encode(`Bearer ${proxyToken}`);
  const lengthsMatch = provided.byteLength === expected.byteLength;

  // Always perform a timing-safe comparison, including when lengths differ.
  return lengthsMatch
    ? crypto.subtle.timingSafeEqual(provided, expected)
    : !crypto.subtle.timingSafeEqual(provided, provided);
}

function validateChatRequest(
  value: unknown,
): { ok: true; value: ChatRequest } | { ok: false; error: string } {
  if (!isRecord(value)) return { ok: false, error: "Request body must be an object" };

  const unexpectedKey = Object.keys(value).find((key) => !ALLOWED_TOP_LEVEL_KEYS.has(key));
  if (unexpectedKey) return { ok: false, error: `Unsupported request field: ${unexpectedKey}` };

  if (value.model !== ALLOWED_MODEL) {
    return { ok: false, error: "Unsupported model" };
  }

  if (!Array.isArray(value.messages) || value.messages.length < 1 || value.messages.length > 2) {
    return { ok: false, error: "Messages must contain one or two entries" };
  }

  let messageCharacters = 0;
  for (const message of value.messages) {
    if (!isRecord(message) || !isExactMessage(message)) {
      return { ok: false, error: "Each message must contain only a supported role and text content" };
    }
    messageCharacters += message.content.length;
  }
  if (messageCharacters > MAX_MESSAGE_CHARACTERS) {
    return { ok: false, error: "Message content is too large" };
  }

  const responseFormat = value.response_format;
  if (!isRecord(responseFormat) || responseFormat.type !== "json_schema") {
    return { ok: false, error: "Structured JSON output is required" };
  }

  const jsonSchema = responseFormat.json_schema;
  if (
    !isRecord(jsonSchema) ||
    typeof jsonSchema.name !== "string" ||
    !ALLOWED_SCHEMA_NAMES.has(jsonSchema.name) ||
    jsonSchema.strict !== true ||
    !isRecord(jsonSchema.schema)
  ) {
    return { ok: false, error: "Unsupported response schema" };
  }

  return { ok: true, value: value as ChatRequest };
}

function isExactMessage(
  value: Record<string, unknown>,
): value is { role: "system" | "user"; content: string } {
  const keys = Object.keys(value);
  return (
    keys.length === 2 &&
    keys.includes("role") &&
    keys.includes("content") &&
    (value.role === "system" || value.role === "user") &&
    typeof value.content === "string" &&
    value.content.length > 0
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function jsonError(
  message: string,
  status: number,
  requestId: string,
  headers: HeadersInit = {},
): Response {
  return corsResponse(JSON.stringify({ error: message }), status, requestId, {
    "Content-Type": "application/json",
    ...headers,
  });
}

/** Retained for browser-based local testing; the native iOS app does not need CORS. */
function corsResponse(
  body: BodyInit | null,
  status: number,
  requestId: string,
  headers: HeadersInit = {},
): Response {
  return new Response(body, {
    status,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "X-Attune-Request-Id": requestId,
      ...headers,
    },
  });
}
