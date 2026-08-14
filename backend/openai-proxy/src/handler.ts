/**
 * Backward-compatible Attune OpenAI gateway.
 *
 * The current iOS app still sends the complete Chat Completions request. This
 * phase validates that request against the three shapes Attune already uses.
 * A later version will move prompts and schemas entirely into this Worker.
 */

import { buildTask, isTaskPath, type BuiltTask } from "./tasks";
import type { GatewayEnv } from "./env";
import {
  actualWeightedUnits,
  reconcileUsage,
  reserveUsage,
  usageHeaders,
  usageModeHeader,
  usageSnapshotForRequest,
  USAGE_PATH,
  UsageRequestError,
  type UsageReservation,
  type UsageSnapshot,
} from "./usage";

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
  env: GatewayEnv,
  upstreamFetch: UpstreamFetch,
): Promise<Response> {
  const startedAt = Date.now();
  const requestId = crypto.randomUUID();
  const url = new URL(request.url);
  const pathname = url.pathname;

  if (request.method === "OPTIONS") {
    return corsResponse(null, 204, requestId);
  }

  const isUsageEndpoint = pathname === USAGE_PATH;
  const isLegacyEndpoint = pathname === ENDPOINT;
  const isServerOwnedTask = isTaskPath(pathname);
  const supportedRequest =
    (request.method === "GET" && isUsageEndpoint) ||
    (request.method === "POST" && (isLegacyEndpoint || isServerOwnedTask));
  if (!supportedRequest) {
    return jsonError("Not found", 404, requestId);
  }

  if (env.AI_ENABLED?.toLowerCase() === "false") {
    return jsonError("AI processing is temporarily unavailable", 503, requestId);
  }

  if (!env.APP_PROXY_TOKEN || !(await hasValidAuthorization(request, env.APP_PROXY_TOKEN))) {
    return jsonError("Unauthorized", 401, requestId);
  }

  if (isUsageEndpoint) {
    try {
      const snapshot = await usageSnapshotForRequest(request, env);
      return corsResponse(JSON.stringify(snapshot ?? unlimitedUsageSnapshot()), 200, requestId, {
        "Content-Type": "application/json",
        ...usageHeaders(snapshot),
        ...usageModeHeader(env),
      });
    } catch (error) {
      return usageErrorResponse(error, requestId);
    }
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
    let reservation: UsageReservation | null;
    try {
      reservation = await reserveUsage(
        request,
        env,
        estimatedTaskUnits(task.value),
      );
    } catch (error) {
      return usageErrorResponse(error, requestId, { "X-Attune-Contract-Version": "1" });
    }
    return performServerOwnedTask(
      task.value,
      env,
      upstreamFetch,
      requestId,
      startedAt,
      reservation,
    );
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
  let reservation: UsageReservation | null;
  try {
    reservation = await reserveUsage(
      request,
      env,
      estimatedLegacyUnits(messageCharacters),
    );
  } catch (error) {
    return usageErrorResponse(error, requestId);
  }

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
    const usageSnapshot = await safeReconcileUsage(
      env,
      reservation,
      actualWeightedUnits(responseBody),
      upstreamResponse.ok,
      requestId,
    );
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
      ...usageHeaders(usageSnapshot),
      ...usageModeHeader(env),
    });
  } catch (error) {
    const usageSnapshot = await safeReconcileUsage(env, reservation, null, false, requestId);
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
      usageHeaders(usageSnapshot),
    );
  }
}

async function performServerOwnedTask(
  task: BuiltTask,
  env: GatewayEnv,
  upstreamFetch: UpstreamFetch,
  requestId: string,
  startedAt: number,
  reservation: UsageReservation | null,
): Promise<Response> {
  try {
    const upstreamResponse = await upstreamFetch(OPENAI_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
        "X-Client-Request-Id": requestId,
      },
      body: JSON.stringify(task.request),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
    const responseBody = await upstreamResponse.arrayBuffer();
    const usageSnapshot = await safeReconcileUsage(
      env,
      reservation,
      actualWeightedUnits(responseBody),
      upstreamResponse.ok,
      requestId,
    );
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
        ...usageHeaders(usageSnapshot),
        ...usageModeHeader(env),
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
        ...usageHeaders(usageSnapshot),
        ...usageModeHeader(env),
      });
    }

    return corsResponse(JSON.stringify(taskOutput.value), 200, requestId, {
      "Content-Type": "application/json",
      "X-Attune-Contract-Version": "1",
      ...usageHeaders(usageSnapshot),
      ...usageModeHeader(env),
    });
  } catch (error) {
    const usageSnapshot = await safeReconcileUsage(env, reservation, null, false, requestId);
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
      {
        "X-Attune-Contract-Version": "1",
        ...usageHeaders(usageSnapshot),
      },
    );
  }
}

function estimatedTaskUnits(task: BuiltTask): number {
  return Math.ceil(task.inputCharacters / 3) + task.request.max_completion_tokens * 4;
}

function estimatedLegacyUnits(messageCharacters: number): number {
  return Math.ceil(messageCharacters / 3) + 16_384 * 4;
}

async function safeReconcileUsage(
  env: GatewayEnv,
  reservation: UsageReservation | null,
  actualUnits: number | null,
  succeeded: boolean,
  requestId: string,
): Promise<UsageSnapshot | null> {
  try {
    return await reconcileUsage(env, reservation, actualUnits, succeeded);
  } catch {
    console.error({ event: "usage_reconcile_failed", requestId });
    return null;
  }
}

function usageErrorResponse(
  error: unknown,
  requestId: string,
  headers: HeadersInit = {},
): Response {
  if (!(error instanceof UsageRequestError)) {
    console.error({ event: "usage_service_failure", requestId });
    return jsonError("AI usage service is temporarily unavailable", 503, requestId, headers);
  }
  const body = {
    error: error.message,
    code: error.code,
    ...(error.snapshot ?? {}),
  };
  return corsResponse(JSON.stringify(body), error.status, requestId, {
    "Content-Type": "application/json",
    ...headers,
    ...usageHeaders(error.snapshot ?? null),
  });
}

function unlimitedUsageSnapshot(): UsageSnapshot {
  return {
    usedUnits: 0,
    limitUnits: 0,
    warningAtUnits: 0,
    warning: false,
    limited: false,
    resetsAt: "",
    period: "",
  };
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
    if (value.title === null) {
      return value.targetValue === null
        && value.unit === null
        && value.timeframe === null
        && value.reason === null
        && value.actionFingerprint === null
        && value.actionFamily === null
        && Array.isArray(value.evidenceItemIds)
        && value.evidenceItemIds.length === 0
        ? { ok: true, value: { suggestion: null } }
        : { ok: false };
    }
    const context = task.suggestionContext;
    if (!context || context.sensitiveEvidence) return { ok: false };
    if (
      typeof value.title !== "string"
      || value.title.trim().length < 3
      || value.title.length > 64
      || value.title.trim().split(/\s+/).length > 8
      || typeof value.targetValue !== "number"
      || !isValidSuggestionTarget(value.targetValue, value.unit)
      || typeof value.unit !== "string"
      || !SUGGESTION_UNITS.has(value.unit)
      || (value.timeframe !== "daily" && value.timeframe !== "weekly")
      || typeof value.reason !== "string"
      || value.reason.trim().length < 1
      || value.reason.length > 140
      || isUnsafeGeneratedSuggestion(`${value.title} ${value.reason}`)
      || typeof value.actionFingerprint !== "string"
      || !/^[a-z0-9]+(?:_[a-z0-9]+){0,7}$/.test(value.actionFingerprint)
      || value.actionFingerprint.length > 80
      || typeof value.actionFamily !== "string"
      || !SUGGESTION_FAMILIES.has(value.actionFamily)
      || !Array.isArray(value.evidenceItemIds)
    ) return { ok: false };
    const suggestionTitle = value.title;
    const evidenceIds = value.evidenceItemIds;
    const actionId = customSuggestionActionId(value.actionFingerprint, value.targetValue, value.unit, value.timeframe);
    if (
      context.blockedActionIds.includes(actionId)
      || context.blockedFingerprints.includes(value.actionFingerprint)
      || context.activeIntentionTexts.some((text) => suggestionTextsMatch(suggestionTitle, text))
      || context.declinedTitles.some((text) => suggestionTextsMatch(suggestionTitle, text))
      || evidenceIds.length < 1
      || evidenceIds.length > 5
      || new Set(evidenceIds).size !== evidenceIds.length
      || evidenceIds.some((id) => typeof id !== "string" || !context.evidenceItemIds.includes(id))
    ) return { ok: false };
    return {
      ok: true,
      value: {
        suggestion: {
          actionId,
          title: value.title.trim(),
          targetValue: value.targetValue,
          unit: value.unit,
          timeframe: value.timeframe,
          reason: value.reason.trim(),
          actionFingerprint: value.actionFingerprint,
          actionFamily: value.actionFamily,
          evidenceItemIds: evidenceIds,
          sourceTitle: null,
          sourceURL: null,
          safetyNote: suggestionSafetyNote(context.topicCategories),
        },
      },
    };
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
      return hasExactKeys(value, ["title", "targetValue", "unit", "timeframe", "reason", "actionFingerprint", "actionFamily", "evidenceItemIds"]) &&
        (value.title === null || typeof value.title === "string") &&
        (value.targetValue === null || typeof value.targetValue === "number") &&
        (value.unit === null || typeof value.unit === "string") &&
        (value.timeframe === null || typeof value.timeframe === "string") &&
        (value.reason === null || typeof value.reason === "string") &&
        (value.actionFingerprint === null || typeof value.actionFingerprint === "string") &&
        (value.actionFamily === null || typeof value.actionFamily === "string") &&
        Array.isArray(value.evidenceItemIds);
  }
}

const SUGGESTION_UNITS = new Set(["pages", "minutes", "sessions", "steps", "reps", "cups", "glasses", "times"]);
const SUGGESTION_FAMILIES = new Set(["movement", "planning", "learning", "connection", "finance_organization", "sleep_routine", "environment", "creativity", "reflection", "other"]);

function isValidSuggestionTarget(target: number, unit: unknown): boolean {
  if (!Number.isFinite(target) || target <= 0 || typeof unit !== "string") return false;
  if (unit === "steps") return target <= 100_000;
  if (unit === "minutes") return target <= 240;
  return target <= 1_000;
}

function customSuggestionActionId(fingerprint: string, target: number, unit: string, timeframe: string): string {
  const targetPart = Number.isInteger(target) ? String(target) : String(target).replace(".", "_");
  return `custom.${fingerprint}.${targetPart}.${unit}.${timeframe}`;
}

function suggestionTextsMatch(lhs: string, rhs: string): boolean {
  const lhsTerms = suggestionCoverageTerms(lhs);
  const rhsTerms = suggestionCoverageTerms(rhs);
  if (lhsTerms.size === 0 || rhsTerms.size === 0) return false;
  const overlap = Array.from(lhsTerms).filter((term) => rhsTerms.has(term)).length;
  const smaller = Math.min(lhsTerms.size, rhsTerms.size);
  return smaller === 1 ? overlap === 1 : overlap >= 2 || overlap / smaller >= 0.6;
}

function suggestionCoverageTerms(value: string): Set<string> {
  const ignored = new Set([
    "a", "an", "and", "at", "daily", "do", "for", "from", "in", "minute", "minutes", "my",
    "of", "one", "short", "take", "the", "this", "times", "to", "today", "two", "weekly",
  ]);
  return new Set(value.toLowerCase().split(/[^a-z0-9]+/).flatMap((raw) => {
    if (ignored.has(raw)) return [];
    let term = raw;
    if (term.length > 5 && term.endsWith("ing")) term = term.slice(0, -3);
    else if (term.length > 4 && term.endsWith("ed")) term = term.slice(0, -2);
    else if (term.length > 4 && term.endsWith("s")) term = term.slice(0, -1);
    if (term === "record") term = "log";
    if (term === "nightly") term = "night";
    return term.length >= 3 ? [term] : [];
  }));
}

function suggestionSafetyNote(categories: string[]): string | null {
  if (categories.includes("fitness_health")) return "Keep this general and adjust it to your abilities. Ask a qualified clinician when health guidance is needed.";
  if (categories.includes("money_finance")) return "This is a general organizing idea, not individualized financial advice.";
  if (categories.includes("relationships_social")) return "Choose an action that feels safe and appropriate for the relationship.";
  return null;
}

function isUnsafeGeneratedSuggestion(value: string): boolean {
  return /\b(calorie|fasting|skip meals?|medication|dosage|prescription|supplement|diagnos|treat|cure|guarantee|which stock|invest|debt settlement|bankruptcy|legal advice)\b/i.test(value);
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
      "Access-Control-Allow-Headers": "Authorization, Content-Type, X-Attune-Installation-Id",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "X-Attune-Request-Id": requestId,
      ...headers,
    },
  });
}
