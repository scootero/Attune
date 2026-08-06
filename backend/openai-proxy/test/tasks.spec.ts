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
