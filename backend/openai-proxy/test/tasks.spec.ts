import { describe, expect, it, vi } from "vitest";
import { handleRequest } from "../src/handler";
import { TASK_PATHS } from "../src/tasks";

const env = {
  APP_PROXY_TOKEN: "test-proxy-token",
  OPENAI_API_KEY: "test-openai-key",
};

const checkInBody = {
  transcript: "I read 10 pages total today and feel calm, eight out of ten.",
  intentions: [
    {
      id: "read-id",
      title: "Read",
      aliases: ["reading"],
      targetValue: 20,
      unit: "pages",
      timeframe: "daily",
    },
  ],
  todaysTotals: { "read-id": 5 },
};

const suggestionBody = {
  topic: { key: "money_finance|spending", title: "Spending", categories: ["money_finance"] },
  evidence: [
    { itemId: "item-1", sessionDate: "2026-08-01T12:00:00Z", quote: "I keep losing track of small purchases." },
    { itemId: "item-2", sessionDate: "2026-08-08T12:00:00Z", quote: "I want a clearer picture of what I spend." },
  ],
  activeIntentions: [],
  declinedActionIds: [],
  rapidTestMode: false,
};

const customSuggestion = (overrides: Record<string, unknown> = {}) => ({
  title: "Log one purchase at night",
  targetValue: 1,
  unit: "times",
  timeframe: "daily",
  reason: "A tiny nightly log turns fuzzy spending into something you can actually see.",
  actionFingerprint: "log_one_purchase",
  actionFamily: "finance_organization",
  evidenceItemIds: ["item-1", "item-2"],
  ...overrides,
});

const taskCases = [
  {
    path: TASK_PATHS.checkIn,
    body: checkInBody,
    schemaName: "checkin_extraction",
    output: { updates: [], moodLabel: "Calm", moodScore: 8 },
  },
  {
    path: TASK_PATHS.intentions,
    body: { transcript: "I want to walk 20 minutes every day." },
    schemaName: "intentions_parse",
    output: {
      intentions: [
        { title: "Walk", target: 20, unit: "minutes", category: "fitness_health", notes: null },
      ],
    },
  },
  {
    path: TASK_PATHS.listening,
    body: {
      transcript: "I need to call Mom tomorrow.",
      priorContext: "I was planning my week.",
      referenceDateTime: "2026-08-06T15:00:00Z",
      timeZone: "America/Chicago",
    },
    schemaName: "items_extraction",
    output: { items: [] },
  },
] as const;

function taskRequest(path: string, body: unknown, authorization = `Bearer ${env.APP_PROXY_TOKEN}`) {
  return new Request(`https://attune.example${path}`, {
    method: "POST",
    headers: { Authorization: authorization, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function chatCompletion(output: unknown, status = 200): Response {
  return new Response(
    JSON.stringify({
      id: "chatcmpl-test",
      object: "chat.completion",
      created: 0,
      model: "gpt-4o-mini",
      choices: [
        {
          index: 0,
          message: { role: "assistant", content: JSON.stringify(output) },
          finish_reason: "stop",
        },
      ],
    }),
    { status, headers: { "Content-Type": "application/json", "x-request-id": "openai-test" } },
  );
}

describe("server-owned v2 task routes", () => {
  for (const testCase of taskCases) {
    it(`builds and returns the ${testCase.schemaName} contract`, async () => {
      let forwardedInit: RequestInit | undefined;
      const upstreamFetch = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
        forwardedInit = init;
        return chatCompletion(testCase.output);
      });

      const response = await handleRequest(
        taskRequest(testCase.path, testCase.body),
        env,
        upstreamFetch,
      );

      expect(response.status).toBe(200);
      expect(response.headers.get("X-Attune-Contract-Version")).toBe("1");
      expect(await response.json()).toEqual(testCase.output);
      const forwarded = JSON.parse(String(forwardedInit?.body));
      expect(forwarded.model).toBe("gpt-4o-mini");
      expect(forwarded.store).toBe(false);
      expect(forwarded.max_completion_tokens).toBeGreaterThan(0);
      expect(forwarded.response_format.json_schema.name).toBe(testCase.schemaName);
      expect(forwarded.messages).toHaveLength(2);
      expect(forwarded.messages[0].role).toBe("system");
      expect(forwarded.messages[1].role).toBe("user");
      expect(forwarded.messages[1].content).toContain(testCase.body.transcript);
      if (testCase.path === TASK_PATHS.listening) {
        expect(forwarded.messages[1].content).toContain("referenceDateTime: 2026-08-06T15:00:00Z");
        expect(forwarded.messages[1].content).toContain("timeZone: America/Chicago");
        expect(forwarded.messages[0].content).toContain("clock time but no date");
      }
    });
  }

  it("returns a fully custom intention instead of choosing from a catalog", async () => {
    let forwardedInit: RequestInit | undefined;
    const contextualBody = {
      ...suggestionBody,
      activeIntentions: [{ id: "read-id", title: "Read", aliases: ["reading"], targetValue: 10, unit: "pages", timeframe: "daily", recentProgressDays: 4 }],
      suggestionHistory: [{ actionId: "custom.teach_idea.1.times.daily", title: "Teach one idea", actionFingerprint: "teach_idea", actionFamily: "learning", outcome: "accepted", decidedAt: "2026-06-01T12:00:00Z" }],
    };
    const response = await handleRequest(
      taskRequest(TASK_PATHS.intentionSuggestion, contextualBody),
      env,
      async (_input, init) => {
        forwardedInit = init;
        return chatCompletion(customSuggestion());
      },
    );
    expect(response.status).toBe(200);
    const body = await response.json() as { suggestion: Record<string, unknown> };
    expect(body.suggestion.title).toBe("Log one purchase at night");
    expect(body.suggestion.actionId).toBe("custom.log_one_purchase.1.times.daily");
    expect(body.suggestion.actionFingerprint).toBe("log_one_purchase");
    expect(body.suggestion.sourceURL).toBeNull();
    expect(body.suggestion.safetyNote).toContain("not individualized financial advice");
    const forwarded = JSON.parse(String(forwardedInit?.body));
    expect(forwarded.messages[0].content).toContain("There is no action catalog");
    expect(forwarded.messages[1].content).not.toContain("allowedActions");
    expect(forwarded.messages[1].content).toContain('"recentProgressDays":4');
    expect(forwarded.messages[1].content).toContain('"actionFingerprint":"teach_idea"');
  });

  it("forwards rapid test mode without weakening the server-owned safety prompt", async () => {
    let forwardedInit: RequestInit | undefined;
    const response = await handleRequest(
      taskRequest(TASK_PATHS.intentionSuggestion, { ...suggestionBody, rapidTestMode: true }),
      env,
      async (_input, init) => {
        forwardedInit = init;
        return chatCompletion(customSuggestion());
      },
    );

    expect(response.status).toBe(200);
    const forwarded = JSON.parse(String(forwardedInit?.body));
    expect(forwarded.messages[1].content).toContain('"rapidTestMode":true');
    expect(forwarded.messages[0].content).toContain("developer evaluation harness");
    expect(forwarded.messages[0].content).toContain("Do not relax");
  });

  it("rejects a non-boolean rapid test mode", async () => {
    const response = await handleRequest(
      taskRequest(TASK_PATHS.intentionSuggestion, { ...suggestionBody, rapidTestMode: "yes" }),
      env,
      vi.fn(),
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "rapidTestMode must be a boolean" });
  });

  it("allows a creative learning action generated for the supplied evidence", async () => {
    const learningBody = { ...suggestionBody, topic: { key: "personal_growth|learning", title: "Learning", categories: ["personal_growth"] } };
    const response = await handleRequest(
      taskRequest(TASK_PATHS.intentionSuggestion, learningBody), env,
      async () => chatCompletion(customSuggestion({
        title: "Teach one idea from memory",
        reason: "Explaining one idea makes the learning theme concrete without adding another study block.",
        actionFingerprint: "teach_idea_from_memory",
        actionFamily: "learning",
      })),
    );
    expect(response.status).toBe(200);
    const body = await response.json() as { suggestion: Record<string, unknown> };
    expect(body.suggestion.title).toBe("Teach one idea from memory");
    expect(body.suggestion.actionId).toBe("custom.teach_idea_from_memory.1.times.daily");
  });

  it("rejects any generated action for sensitive individualized evidence", async () => {
    const sensitiveBody = { ...suggestionBody, topic: { key: "fitness_health|pain", title: "Pain", categories: ["fitness_health"] }, evidence: [
      { itemId: "item-1", sessionDate: "2026-08-01T12:00:00Z", quote: "I have severe pain after my medication." },
      { itemId: "item-2", sessionDate: "2026-08-08T12:00:00Z", quote: "The injury keeps getting worse." },
    ] };
    const response = await handleRequest(taskRequest(TASK_PATHS.intentionSuggestion, sensitiveBody), env, async () => chatCompletion(customSuggestion({
      title: "Take a short walk",
      actionFingerprint: "take_short_walk",
      actionFamily: "movement",
    })));
    expect(response.status).toBe(502);
  });

  it("returns no suggestion when the conservative model declines", async () => {
    const response = await handleRequest(
      taskRequest(TASK_PATHS.intentionSuggestion, suggestionBody),
      env,
      async () => chatCompletion({ title: null, targetValue: null, unit: null, timeframe: null, reason: null, actionFingerprint: null, actionFamily: null, evidenceItemIds: [] }),
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ suggestion: null });
  });

  it("rejects invalid custom fields and orphaned suggestion evidence", async () => {
    for (const output of [
      customSuggestion({ actionFingerprint: "Not normalized" }),
      customSuggestion({ targetValue: 0 }),
      customSuggestion({ evidenceItemIds: ["orphan"] }),
      customSuggestion({ title: "Skip one meal daily", reason: "Cut calories to guarantee weight loss.", actionFingerprint: "skip_one_meal", actionFamily: "other" }),
    ]) {
      const response = await handleRequest(taskRequest(TASK_PATHS.intentionSuggestion, suggestionBody), env, async () => chatCompletion(output));
      expect(response.status).toBe(502);
    }
  });

  it("rejects active-intention duplicates and permanently declined close variants", async () => {
    const fitnessBody = {
      ...suggestionBody,
      topic: { key: "fitness_health|walking", title: "Walking", categories: ["fitness_health"] },
      activeIntentions: [{ title: "Walk", aliases: [] }],
    };
    const activeDuplicate = await handleRequest(taskRequest(TASK_PATHS.intentionSuggestion, fitnessBody), env, async () => chatCompletion(customSuggestion({ title: "Take a short walk", actionFingerprint: "take_short_walk", actionFamily: "movement" })));
    expect(activeDuplicate.status).toBe(502);

    const declinedBody = {
      ...suggestionBody,
      suggestionHistory: [{
        actionId: "custom.log_one_purchase.1.times.daily",
        title: "Log one purchase at night",
        actionFingerprint: "log_one_purchase",
        actionFamily: "finance_organization",
        outcome: "declined",
        decidedAt: "2026-08-10T12:00:00Z",
      }],
    };
    const exact = await handleRequest(taskRequest(TASK_PATHS.intentionSuggestion, declinedBody), env, async () => chatCompletion(customSuggestion()));
    expect(exact.status).toBe(502);
    const closeVariant = await handleRequest(taskRequest(TASK_PATHS.intentionSuggestion, declinedBody), env, async () => chatCompletion(customSuggestion({ title: "Record one nightly purchase", actionFingerprint: "record_nightly_purchase" })));
    expect(closeVariant.status).toBe(502);
    const distinct = await handleRequest(taskRequest(TASK_PATHS.intentionSuggestion, declinedBody), env, async () => chatCompletion(customSuggestion({ title: "Set a weekly money date", targetValue: 1, unit: "sessions", timeframe: "weekly", actionFingerprint: "weekly_money_date" })));
    expect(distinct.status).toBe(200);

    const recentlyAcceptedBody = {
      ...suggestionBody,
      suggestionHistory: [{ actionId: "custom.log_one_purchase.1.times.daily", title: "Log one purchase at night", actionFingerprint: "log_one_purchase", actionFamily: "finance_organization", outcome: "accepted", decidedAt: "2026-08-13T12:00:00Z" }],
    };
    const recentRepeat = await handleRequest(taskRequest(TASK_PATHS.intentionSuggestion, recentlyAcceptedBody), env, async () => chatCompletion(customSuggestion()));
    expect(recentRepeat.status).toBe(502);
  });

  it("does not accept client-owned model, prompt, or schema policy", async () => {
    const response = await handleRequest(
      taskRequest(TASK_PATHS.intentions, {
        transcript: "I want to walk.",
        model: "gpt-4o",
      }),
      env,
      vi.fn(),
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "Unsupported request field: model" });
  });

  it("validates check-in totals against supplied intentions", async () => {
    const response = await handleRequest(
      taskRequest(TASK_PATHS.checkIn, {
        ...checkInBody,
        todaysTotals: { "unknown-id": 4 },
      }),
      env,
      vi.fn(),
    );

    expect(response.status).toBe(400);
  });

  it("validates Listening temporal context as a pair", async () => {
    const response = await handleRequest(
      taskRequest(TASK_PATHS.listening, {
        transcript: "Dentist tomorrow at 2 PM.",
        referenceDateTime: "2026-08-06T15:00:00Z",
      }),
      env,
      vi.fn(),
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "referenceDateTime and timeZone must be supplied together",
    });
  });

  it("requires the legacy token until App Attest replaces it", async () => {
    const upstreamFetch = vi.fn();
    const response = await handleRequest(
      taskRequest(TASK_PATHS.listening, { transcript: "A short thought." }, "Bearer wrong"),
      env,
      upstreamFetch,
    );

    expect(response.status).toBe(401);
    expect(upstreamFetch).not.toHaveBeenCalled();
  });

  it("rejects malformed successful provider responses", async () => {
    const response = await handleRequest(
      taskRequest(TASK_PATHS.intentions, { transcript: "I want to walk." }),
      env,
      async () => new Response(JSON.stringify({ choices: [] }), { status: 200 }),
    );

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: "AI provider returned an invalid response" });
  });

  it("passes provider error details through for diagnosis", async () => {
    const errorBody = { error: { code: "credit_balance_exhausted" } };
    const response = await handleRequest(
      taskRequest(TASK_PATHS.listening, { transcript: "A short thought." }),
      env,
      async () =>
        new Response(JSON.stringify(errorBody), {
          status: 429,
          headers: { "Content-Type": "application/json" },
        }),
    );

    expect(response.status).toBe(429);
    expect(await response.json()).toEqual(errorBody);
  });
});
