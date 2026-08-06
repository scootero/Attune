/** Server-owned AI task contracts for the parallel v2 rollout. */

export const TASK_PATHS = {
  checkIn: "/v2/check-ins/extract",
  intentions: "/v2/intentions/parse",
  listening: "/v2/listening/extract",
} as const;

export type TaskPath = (typeof TASK_PATHS)[keyof typeof TASK_PATHS];

export type ServerOwnedChatRequest = {
  model: "gpt-4o-mini";
  messages: Array<{ role: "system" | "user"; content: string }>;
  response_format: {
    type: "json_schema";
    json_schema: {
      name: string;
      strict: true;
      schema: Record<string, unknown>;
    };
  };
  max_completion_tokens: number;
  store: false;
};

export type BuiltTask = {
  request: ServerOwnedChatRequest;
  taskName: "check_in" | "intentions" | "listening";
  inputCharacters: number;
};

type ValidationResult =
  | { ok: true; value: BuiltTask }
  | { ok: false; error: string };

type IntentionContext = {
  id: string;
  title: string;
  aliases: string[];
  targetValue: number;
  unit: string;
  timeframe: string;
};

const MODEL = "gpt-4o-mini" as const;
const MAX_TRANSCRIPT_CHARACTERS = 50_000;
const MAX_PRIOR_CONTEXT_CHARACTERS = 10_000;
const MAX_INTENTIONS = 10;

export function isTaskPath(pathname: string): pathname is TaskPath {
  return Object.values(TASK_PATHS).includes(pathname as TaskPath);
}

export function buildTask(path: TaskPath, rawBody: unknown): ValidationResult {
  switch (path) {
    case TASK_PATHS.checkIn:
      return buildCheckInTask(rawBody);
    case TASK_PATHS.intentions:
      return buildIntentionsTask(rawBody);
    case TASK_PATHS.listening:
      return buildListeningTask(rawBody);
  }
}

function buildCheckInTask(rawBody: unknown): ValidationResult {
  if (!isRecord(rawBody)) return invalid("Request body must be an object");
  const keyError = validateKeys(rawBody, ["transcript", "intentions", "todaysTotals"]);
  if (keyError) return invalid(keyError);

  const transcript = validateText(rawBody.transcript, "transcript", MAX_TRANSCRIPT_CHARACTERS);
  if (!transcript.ok) return invalid(transcript.error);

  if (
    !Array.isArray(rawBody.intentions) ||
    rawBody.intentions.length < 1 ||
    rawBody.intentions.length > MAX_INTENTIONS
  ) {
    return invalid(`intentions must contain between 1 and ${MAX_INTENTIONS} items`);
  }

  const intentions: IntentionContext[] = [];
  for (const value of rawBody.intentions) {
    const intention = validateIntention(value);
    if (!intention.ok) return invalid(intention.error);
    intentions.push(intention.value);
  }

  if (!isRecord(rawBody.todaysTotals)) {
    return invalid("todaysTotals must be an object");
  }
  const intentionIds = new Set(intentions.map((intention) => intention.id));
  const totalsEntries = Object.entries(rawBody.todaysTotals);
  if (totalsEntries.length > MAX_INTENTIONS) {
    return invalid(`todaysTotals may contain at most ${MAX_INTENTIONS} entries`);
  }
  const totals: Record<string, number> = {};
  for (const [id, value] of totalsEntries) {
    if (!intentionIds.has(id) || !isNonnegativeFiniteNumber(value)) {
      return invalid("todaysTotals must contain nonnegative totals for supplied intentions only");
    }
    totals[id] = value;
  }

  const systemMessage = CHECK_IN_SYSTEM_PROMPT;
  const userMessage = buildCheckInUserMessage(transcript.value, intentions, totals);
  return valid({
    taskName: "check_in",
    inputCharacters: systemMessage.length + userMessage.length,
    request: chatRequest(systemMessage, userMessage, CHECK_IN_SCHEMA, 2_000),
  });
}

function buildIntentionsTask(rawBody: unknown): ValidationResult {
  if (!isRecord(rawBody)) return invalid("Request body must be an object");
  const keyError = validateKeys(rawBody, ["transcript"]);
  if (keyError) return invalid(keyError);
  const transcript = validateText(rawBody.transcript, "transcript", MAX_TRANSCRIPT_CHARACTERS);
  if (!transcript.ok) return invalid(transcript.error);

  const systemMessage = INTENTIONS_SYSTEM_PROMPT;
  const userMessage = buildIntentionsUserMessage(transcript.value);
  return valid({
    taskName: "intentions",
    inputCharacters: systemMessage.length + userMessage.length,
    request: chatRequest(systemMessage, userMessage, INTENTIONS_SCHEMA, 2_000),
  });
}

function buildListeningTask(rawBody: unknown): ValidationResult {
  if (!isRecord(rawBody)) return invalid("Request body must be an object");
  const keyError = validateKeys(rawBody, ["transcript", "priorContext"]);
  if (keyError) return invalid(keyError);
  const transcript = validateText(rawBody.transcript, "transcript", MAX_TRANSCRIPT_CHARACTERS);
  if (!transcript.ok) return invalid(transcript.error);

  let priorContext: string | undefined;
  if (rawBody.priorContext !== undefined && rawBody.priorContext !== null) {
    const validated = validateText(
      rawBody.priorContext,
      "priorContext",
      MAX_PRIOR_CONTEXT_CHARACTERS,
      true,
    );
    if (!validated.ok) return invalid(validated.error);
    priorContext = validated.value;
  }

  const systemMessage = LISTENING_SYSTEM_PROMPT;
  const userMessage = buildListeningUserMessage(transcript.value, priorContext);
  return valid({
    taskName: "listening",
    inputCharacters: systemMessage.length + userMessage.length,
    request: chatRequest(systemMessage, userMessage, LISTENING_SCHEMA, 4_096),
  });
}

function chatRequest(
  systemMessage: string,
  userMessage: string,
  jsonSchema: ServerOwnedChatRequest["response_format"]["json_schema"],
  maxCompletionTokens: number,
): ServerOwnedChatRequest {
  return {
    model: MODEL,
    messages: [
      { role: "system", content: systemMessage },
      { role: "user", content: userMessage },
    ],
    response_format: { type: "json_schema", json_schema: jsonSchema },
    max_completion_tokens: maxCompletionTokens,
    store: false,
  };
}

function validateIntention(
  value: unknown,
): { ok: true; value: IntentionContext } | { ok: false; error: string } {
  if (!isRecord(value)) return { ok: false, error: "Each intention must be an object" };
  const keyError = validateKeys(value, [
    "id",
    "title",
    "aliases",
    "targetValue",
    "unit",
    "timeframe",
  ]);
  if (keyError) return { ok: false, error: keyError };

  const id = validateText(value.id, "intention.id", 128);
  const title = validateText(value.title, "intention.title", 120);
  const unit = validateText(value.unit, "intention.unit", 40);
  const timeframe = validateText(value.timeframe, "intention.timeframe", 40);
  if (!id.ok) return id;
  if (!title.ok) return title;
  if (!unit.ok) return unit;
  if (!timeframe.ok) return timeframe;
  if (!isNonnegativeFiniteNumber(value.targetValue) || value.targetValue === 0) {
    return { ok: false, error: "intention.targetValue must be a positive number" };
  }

  if (!Array.isArray(value.aliases) || value.aliases.length > 20) {
    return { ok: false, error: "intention.aliases must be an array with at most 20 items" };
  }
  const aliases: string[] = [];
  for (const alias of value.aliases) {
    const validated = validateText(alias, "intention.alias", 80, true);
    if (!validated.ok) return validated;
    aliases.push(validated.value);
  }

  return {
    ok: true,
    value: {
      id: id.value,
      title: title.value,
      aliases,
      targetValue: value.targetValue,
      unit: unit.value,
      timeframe: timeframe.value,
    },
  };
}

function validateText(
  value: unknown,
  field: string,
  maximumCharacters: number,
  allowEmpty = false,
): { ok: true; value: string } | { ok: false; error: string } {
  if (typeof value !== "string") return { ok: false, error: `${field} must be text` };
  const trimmed = value.trim();
  if (!allowEmpty && trimmed.length === 0) return { ok: false, error: `${field} must not be empty` };
  if (value.length > maximumCharacters) {
    return { ok: false, error: `${field} exceeds ${maximumCharacters} characters` };
  }
  return { ok: true, value };
}

function validateKeys(value: Record<string, unknown>, allowed: string[]): string | undefined {
  const allowedKeys = new Set(allowed);
  const unsupported = Object.keys(value).find((key) => !allowedKeys.has(key));
  return unsupported ? `Unsupported request field: ${unsupported}` : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNonnegativeFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function valid(value: BuiltTask): ValidationResult {
  return { ok: true, value };
}

function invalid(error: string): ValidationResult {
  return { ok: false, error };
}

function buildCheckInUserMessage(
  transcript: string,
  intentions: IntentionContext[],
  todaysTotals: Record<string, number>,
): string {
  let message = "CURRENT INTENTIONS:\n";
  for (const intention of intentions) {
    message += `- id: ${intention.id} | title: ${intention.title} | aliases: ${intention.aliases.join(",")} | target: ${intention.targetValue} ${intention.unit} | timeframe: ${intention.timeframe}\n`;
  }
  message += "\nTODAY'S TOTALS SO FAR (do not duplicate; add to or replace as appropriate):\n";
  for (const [id, total] of Object.entries(todaysTotals)) message += `- ${id}: ${total}\n`;
  message += `\nTRANSCRIPT:\n${transcript}`;
  return message;
}

function buildIntentionsUserMessage(transcript: string): string {
  return `Transcript:
${transcript}

Output JSON schema:
{
  "intentions": [
    {
      "title": "Walk",
      "target": 20,
      "unit": "minutes",
      "category": "fitness_health",
      "notes": null
    }
  ]
}
Rules:
- Provide an array of intentions (can be empty when nothing is found).
- title: required string.
- target: number; if missing default to 1.
- unit: normalized string; if missing default to "times".
- category: best-effort from allowed categories; null when uncertain.
- notes: optional; null when none.
Return JSON only. // detailed contract plus rules for the model`;
}

function buildListeningUserMessage(transcript: string, priorContext?: string): string {
  let message = "";
  if (priorContext) message += `PRIOR CONTEXT (from previous segment):\n${priorContext}\n\n`;
  message += `TRANSCRIPT:\n${transcript}`;
  return message;
}

const CHECK_IN_SYSTEM_PROMPT = `You extract progress updates and optional mood from daily check-in transcripts.

Given the user's current intentions (with target values and units) and today's progress so far, identify any explicit progress mentioned in the transcript.

RULES:
- Only extract updates that clearly reference one of the provided intentions (match by intentionId).
- Titles and aliases are equivalent signals: if transcript mentions a title or any alias, map to that intentionId.
- updateType: "INCREMENT" when the user adds to their total (e.g., "I read 3 more pages").
- updateType: "TOTAL" when the user states an absolute total (e.g., "I've read 10 pages today").
- amount: numeric value only. Never negative.
- unit: must match the intention's unit (pages, minutes, sessions, etc.).
- confidence: 0.0 to 1.0 — how certain you are this extraction is correct.
- evidence: short exact quote from transcript that supports this update (optional).

TIME (required fields; use null when no explicit time):
- tookPlaceLocalTime: { "hour24": 0-23, "minute": 0-59 } when user states a clock time (e.g. "at 9 AM", "this morning at 9"); else null.
- timeInterpretation: "explicit_time" when tookPlaceLocalTime is set; "just_now" when user says "just now"/"just went"; "unspecified" when no time mentioned. Never null — use "unspecified" as default.

MOOD (optional, Slice A):
- moodLabel: one word or short phrase (e.g., "Calm", "Anxious", "Tired") or null.
- moodScore: integer 0 to 10 (0 = lowest, 10 = highest; 5 = neutral) or null.

Return ONLY valid JSON matching the schema. No markdown, no explanations.
If no progress or mood is clearly stated, return: {"updates": [], "moodLabel": null, "moodScore": null}`;

const INTENTIONS_SYSTEM_PROMPT = `You convert a user’s spoken intentions into structured JSON for an intentions app. Output JSON only. // directive for JSON-only output
Unit normalization rules: minutes/min -> "minutes"; pages/page -> "pages"; times/time -> "times"; miles/mi -> "miles"; steps -> "steps"; sessions -> "sessions"; reps -> "reps"; cups -> "cups"; glasses -> "glasses". Unknown -> "times". // embeds normalization guidance
Category inference: fitness/health -> fitness_health; work/coding/business -> career_work; money/budget -> money_finance; learning/reading -> personal_growth; social/friends/date -> relationships_social; stress/overwhelm -> stress_load; calm/meditation/sleep -> peace_wellbeing; if uncertain -> null. // embeds category mapping guidance`;

const LISTENING_SYSTEM_PROMPT = `You are an extraction assistant that identifies meaningful items from voice transcripts.

Extract ONLY items that are:
- High-confidence (you're sure this is what the user meant)
- Meaningful (worth tracking or acting on)
- Clearly stated (not vague or implied)

SPARSE BY DEFAULT: Returning an empty items array is completely valid and preferred over low-quality extractions.

ALLOWED TYPES:
- "event": time-bound occurrences (meetings, appointments, deadlines)
- "intention": things the user plans or wants to do
- "commitment": promises or obligations to self or others
- "state": observations about current conditions, feelings, or situations

ALLOWED CATEGORIES (can assign multiple):
- "fitness_health": physical health, exercise, medical, sleep, nutrition
- "career_work": job, projects, professional development
- "money_finance": finances, purchases, investments, budgets
- "personal_growth": learning, skills, self-improvement, hobbies
- "relationships_social": family, friends, social connections
- "stress_load": stress, overwhelm, burnout, pressure
- "peace_wellbeing": calm, contentment, mental health, balance

REQUIRED TITLE (1–3 words, max 4 if needed):
- Use noun phrase / simplest phrasing
- Avoid filler words: "like", "felt", "start", "would", "going to", "want to"
- Avoid duplicate words: "New Puppy" not "New Puppy New Puppy"
- Prefer compound words if natural: "Workout" over "Work Out"
- Do NOT echo transcript phrasing verbatim
- Examples: "Workout", "Call Mom", "Doctor Appointment", "Budget Review"

REQUIRED PROVENANCE:
- sourceQuote: exact words from transcript
- contextBefore: a few words before the quote (if helpful)
- contextAfter: a few words after the quote (if helpful)

REQUIRED SCORES (0.0 to 1.0):
- confidence: how certain you are this extraction is CORRECT (not how important it is)
  → Score based on clarity and certainty of the extraction, not the item's significance
- strength: how important/impactful this item seems (this will be overridden by heuristics)

REQUIRED FINGERPRINT (best-effort concept label):
- fingerprint: a short concept label like "workout" or "call_mom" (your best guess)
  → Do NOT include time qualifiers (today, tomorrow, daily, weekly, etc.)
  → Do NOT attempt semantic grouping or synonym matching
  → Just provide a simple label for this specific mention

CALENDAR CANDIDATES:
- For event types, optionally provide calendarCandidate with:
  - suggestedTitle, startISO8601, endISO8601, isAllDay, notes
- Only include if date/time information is explicit or strongly implied

Return ONLY valid JSON matching the schema. No markdown, no explanations.
If nothing meets the quality bar, return: {"items": []}`;

const CHECK_IN_SCHEMA: ServerOwnedChatRequest["response_format"]["json_schema"] = {
  name: "checkin_extraction",
  strict: true,
  schema: {
    type: "object",
    properties: {
      updates: {
        type: "array",
        items: {
          type: "object",
          properties: {
            intentionId: { type: "string" },
            updateType: { type: "string" },
            amount: { type: "number" },
            unit: { type: "string" },
            confidence: { type: "number" },
            evidence: { type: ["string", "null"] },
            tookPlaceLocalTime: {
              type: ["object", "null"],
              properties: { hour24: { type: "integer" }, minute: { type: "integer" } },
              required: ["hour24", "minute"],
              additionalProperties: false,
            },
            timeInterpretation: { type: ["string", "null"] },
          },
          required: [
            "intentionId",
            "updateType",
            "amount",
            "unit",
            "confidence",
            "evidence",
            "tookPlaceLocalTime",
            "timeInterpretation",
          ],
          additionalProperties: false,
        },
      },
      moodLabel: { type: ["string", "null"] },
      moodScore: { type: ["integer", "null"] },
    },
    required: ["updates", "moodLabel", "moodScore"],
    additionalProperties: false,
  },
};

const INTENTIONS_SCHEMA: ServerOwnedChatRequest["response_format"]["json_schema"] = {
  name: "intentions_parse",
  strict: true,
  schema: {
    type: "object",
    properties: {
      intentions: {
        type: "array",
        items: {
          type: "object",
          properties: {
            title: { type: "string" },
            target: { type: ["number", "null"] },
            unit: { type: ["string", "null"] },
            category: { type: ["string", "null"] },
            notes: { type: ["string", "null"] },
          },
          required: ["title", "target", "unit", "category", "notes"],
          additionalProperties: false,
        },
      },
    },
    required: ["intentions"],
    additionalProperties: false,
  },
};

const LISTENING_SCHEMA: ServerOwnedChatRequest["response_format"]["json_schema"] = {
  name: "items_extraction",
  strict: true,
  schema: {
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            type: { type: "string" },
            title: { type: "string" },
            summary: { type: "string" },
            categories: { type: "array", items: { type: "string" } },
            confidence: { type: "number" },
            strength: { type: "number" },
            sourceQuote: { type: "string" },
            contextBefore: { type: ["string", "null"] },
            contextAfter: { type: ["string", "null"] },
            fingerprint: { type: "string" },
            calendarCandidate: {
              type: ["object", "null"],
              properties: {
                suggestedTitle: { type: ["string", "null"] },
                startISO8601: { type: ["string", "null"] },
                endISO8601: { type: ["string", "null"] },
                isAllDay: { type: ["boolean", "null"] },
                notes: { type: ["string", "null"] },
              },
              required: ["suggestedTitle", "startISO8601", "endISO8601", "isAllDay", "notes"],
              additionalProperties: false,
            },
          },
          required: [
            "type",
            "title",
            "summary",
            "categories",
            "confidence",
            "strength",
            "sourceQuote",
            "contextBefore",
            "contextAfter",
            "fingerprint",
            "calendarCandidate",
          ],
          additionalProperties: false,
        },
      },
    },
    required: ["items"],
    additionalProperties: false,
  },
};
