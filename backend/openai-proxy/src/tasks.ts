/** Server-owned AI task contracts for the parallel v2 rollout. */

export const TASK_PATHS = {
  checkIn: "/v2/check-ins/extract",
  intentions: "/v2/intentions/parse",
  listening: "/v2/listening/extract",
  intentionSuggestion: "/v2/intentions/suggest-action",
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
  taskName: "check_in" | "intentions" | "listening" | "intention_suggestion";
  inputCharacters: number;
  suggestionContext?: {
    evidenceItemIds: string[];
    blockedActionIds: string[];
    blockedFingerprints: string[];
    declinedTitles: string[];
    activeIntentionTexts: string[];
    topicCategories: string[];
    sensitiveEvidence: boolean;
  };
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
    case TASK_PATHS.intentionSuggestion:
      return buildIntentionSuggestionTask(rawBody);
  }
}

function buildIntentionSuggestionTask(rawBody: unknown): ValidationResult {
  if (!isRecord(rawBody)) return invalid("Request body must be an object");
  const keyError = validateKeys(rawBody, ["topic", "evidence", "activeIntentions", "declinedActionIds", "suggestionHistory", "rapidTestMode"]);
  if (keyError) return invalid(keyError);
  if (rawBody.rapidTestMode !== undefined && typeof rawBody.rapidTestMode !== "boolean") {
    return invalid("rapidTestMode must be a boolean");
  }
  if (!isRecord(rawBody.topic)) return invalid("topic must be an object");
  const topicKeyError = validateKeys(rawBody.topic, ["key", "title", "categories"]);
  if (topicKeyError) return invalid(topicKeyError);
  const key = validateText(rawBody.topic.key, "topic.key", 160);
  const title = validateText(rawBody.topic.title, "topic.title", 120);
  if (!key.ok) return invalid(key.error);
  if (!title.ok) return invalid(title.error);
  if (!Array.isArray(rawBody.topic.categories) || rawBody.topic.categories.length > 10 || !rawBody.topic.categories.every((v) => typeof v === "string" && v.length <= 50)) {
    return invalid("topic.categories must be an array of short strings");
  }
  if (!Array.isArray(rawBody.evidence) || rawBody.evidence.length < 2 || rawBody.evidence.length > 5) {
    return invalid("evidence must contain between 2 and 5 items");
  }
  const evidence: Array<{ itemId: string; sessionDate: string; quote: string }> = [];
  for (const value of rawBody.evidence) {
    if (!isRecord(value)) return invalid("Each evidence item must be an object");
    const error = validateKeys(value, ["itemId", "sessionDate", "quote"]);
    if (error) return invalid(error);
    const itemId = validateText(value.itemId, "evidence.itemId", 128);
    const sessionDate = validateText(value.sessionDate, "evidence.sessionDate", 64);
    const quote = validateText(value.quote, "evidence.quote", 240);
    if (!itemId.ok) return invalid(itemId.error);
    if (!sessionDate.ok || !Number.isFinite(Date.parse(sessionDate.value))) return invalid("evidence.sessionDate must be ISO8601");
    if (!quote.ok) return invalid(quote.error);
    evidence.push({ itemId: itemId.value, sessionDate: sessionDate.value, quote: quote.value });
  }
  if (!Array.isArray(rawBody.activeIntentions) || rawBody.activeIntentions.length > MAX_INTENTIONS) return invalid("activeIntentions may contain at most 10 items");
  const activeIntentions: Array<{ id?: string; title: string; aliases: string[]; targetValue?: number; unit?: string; timeframe?: string; recentProgressDays?: number }> = [];
  for (const value of rawBody.activeIntentions) {
    if (!isRecord(value)) return invalid("Each active intention must be an object");
    const error = validateKeys(value, ["id", "title", "aliases", "targetValue", "unit", "timeframe", "recentProgressDays"]);
    if (error) return invalid(error);
    const activeTitle = validateText(value.title, "activeIntention.title", 120);
    if (!activeTitle.ok || !Array.isArray(value.aliases) || value.aliases.length > 20 || !value.aliases.every((v) => typeof v === "string" && v.length <= 80)) return invalid("Invalid active intention");
    if (value.id !== undefined && (typeof value.id !== "string" || value.id.length > 128)) return invalid("Invalid active intention id");
    if (value.targetValue !== undefined && (!isNonnegativeFiniteNumber(value.targetValue) || value.targetValue === 0)) return invalid("Invalid active intention target");
    if (value.unit !== undefined && (typeof value.unit !== "string" || value.unit.length > 40)) return invalid("Invalid active intention unit");
    if (value.timeframe !== undefined && (value.timeframe !== "daily" && value.timeframe !== "weekly")) return invalid("Invalid active intention timeframe");
    if (value.recentProgressDays !== undefined && (typeof value.recentProgressDays !== "number" || !Number.isInteger(value.recentProgressDays) || value.recentProgressDays < 0 || value.recentProgressDays > 14)) return invalid("Invalid active intention progress context");
    activeIntentions.push({
      id: value.id as string | undefined,
      title: activeTitle.value,
      aliases: value.aliases as string[],
      targetValue: value.targetValue as number | undefined,
      unit: value.unit as string | undefined,
      timeframe: value.timeframe as string | undefined,
      recentProgressDays: value.recentProgressDays as number | undefined,
    });
  }
  if (!Array.isArray(rawBody.declinedActionIds) || rawBody.declinedActionIds.length > 100 || !rawBody.declinedActionIds.every((v) => typeof v === "string" && v.length <= 100)) return invalid("declinedActionIds must be an array of action IDs");

  const suggestionHistory: Array<{ actionId: string; title?: string; actionFingerprint?: string; actionFamily?: string; outcome: "accepted" | "declined"; decidedAt: string }> = [];
  if (rawBody.suggestionHistory !== undefined) {
    if (!Array.isArray(rawBody.suggestionHistory) || rawBody.suggestionHistory.length > 100) return invalid("suggestionHistory may contain at most 100 items");
    for (const value of rawBody.suggestionHistory) {
      if (!isRecord(value)) return invalid("Each suggestion history item must be an object");
      const error = validateKeys(value, ["actionId", "title", "actionFingerprint", "actionFamily", "outcome", "decidedAt"]);
      if (error) return invalid(error);
      const actionId = validateText(value.actionId, "suggestionHistory.actionId", 100);
      const decidedAt = validateText(value.decidedAt, "suggestionHistory.decidedAt", 64);
      if (!actionId.ok || !decidedAt.ok || !Number.isFinite(Date.parse(decidedAt.value))) return invalid("Invalid suggestion history item");
      if (value.outcome !== "accepted" && value.outcome !== "declined") return invalid("Invalid suggestion history outcome");
      for (const optionalKey of ["title", "actionFingerprint", "actionFamily"] as const) {
        if (value[optionalKey] !== undefined && (typeof value[optionalKey] !== "string" || value[optionalKey].length > 120)) return invalid(`Invalid suggestion history ${optionalKey}`);
      }
      suggestionHistory.push({
        actionId: actionId.value,
        title: value.title as string | undefined,
        actionFingerprint: value.actionFingerprint as string | undefined,
        actionFamily: value.actionFamily as string | undefined,
        outcome: value.outcome,
        decidedAt: decidedAt.value,
      });
    }
  }

  const topicCategories = rawBody.topic.categories as string[];
  const evidenceText = `${title.value} ${evidence.map((item) => item.quote).join(" ")}`.toLowerCase();
  const declinedActionIds = rawBody.declinedActionIds as string[];
  const declinedHistory = suggestionHistory.filter((item) => item.outcome === "declined");
  const recentAccepted = suggestionHistory.filter((item) => item.outcome === "accepted" && Date.now() - Date.parse(item.decidedAt) < 60 * 24 * 60 * 60 * 1_000);
  const blockedActionIds = [...new Set([...declinedActionIds, ...declinedHistory.map((item) => item.actionId), ...recentAccepted.map((item) => item.actionId)])];
  const blockedFingerprints = [...new Set([...declinedHistory, ...recentAccepted].flatMap((item) => item.actionFingerprint ? [item.actionFingerprint] : []))];
  const declinedTitles = declinedHistory.flatMap((item) => item.title ? [item.title] : []);
  const sensitiveEvidence = isSensitiveSuggestionEvidence(evidenceText);
  const systemMessage = INTENTION_SUGGESTION_SYSTEM_PROMPT;
  const userMessage = JSON.stringify({
    topic: { key: key.value, title: title.value, categories: topicCategories },
    evidence,
    activeIntentions,
    suggestionHistory,
    rapidTestMode: rawBody.rapidTestMode === true,
    avoidExactFingerprints: blockedFingerprints,
    avoidCloseVariantsOf: declinedTitles,
  });
  return valid({
    taskName: "intention_suggestion",
    inputCharacters: systemMessage.length + userMessage.length,
    suggestionContext: {
      evidenceItemIds: evidence.map((item) => item.itemId),
      blockedActionIds,
      blockedFingerprints,
      declinedTitles,
      activeIntentionTexts: activeIntentions.map((item) => [item.title, ...item.aliases].join(" ")),
      topicCategories,
      sensitiveEvidence,
    },
    request: chatRequest(systemMessage, userMessage, INTENTION_SUGGESTION_SCHEMA, 800),
  });
}

function isSensitiveSuggestionEvidence(value: string): boolean {
  return /\b(chest pain|suicid|self[- ]?harm|eating disorder|anorexia|bulimia|pregnan|medication|prescription|injur|severe pain|can'?t breathe|cannot breathe|investment advice|which stock|bankrupt|debt settlement)\b/.test(value);
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
  const keyError = validateKeys(rawBody, [
    "transcript",
    "priorContext",
    "referenceDateTime",
    "timeZone",
  ]);
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

  let referenceDateTime: string | undefined;
  let timeZone: string | undefined;
  const hasReferenceDateTime = rawBody.referenceDateTime !== undefined;
  const hasTimeZone = rawBody.timeZone !== undefined;
  if (hasReferenceDateTime !== hasTimeZone) {
    return invalid("referenceDateTime and timeZone must be supplied together");
  }
  if (hasReferenceDateTime && hasTimeZone) {
    const validatedDateTime = validateText(rawBody.referenceDateTime, "referenceDateTime", 64);
    const validatedTimeZone = validateText(rawBody.timeZone, "timeZone", 100);
    if (!validatedDateTime.ok) return invalid(validatedDateTime.error);
    if (!validatedTimeZone.ok) return invalid(validatedTimeZone.error);
    if (!Number.isFinite(Date.parse(validatedDateTime.value))) {
      return invalid("referenceDateTime must be an ISO8601 date-time");
    }
    try {
      new Intl.DateTimeFormat("en-US", { timeZone: validatedTimeZone.value }).format();
    } catch {
      return invalid("timeZone must be a valid IANA time zone");
    }
    referenceDateTime = validatedDateTime.value;
    timeZone = validatedTimeZone.value;
  }

  const systemMessage = LISTENING_SYSTEM_PROMPT;
  const userMessage = buildListeningUserMessage(
    transcript.value,
    priorContext,
    referenceDateTime,
    timeZone,
  );
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

function buildListeningUserMessage(
  transcript: string,
  priorContext?: string,
  referenceDateTime?: string,
  timeZone?: string,
): string {
  let message = "";
  if (referenceDateTime && timeZone) {
    message += "REFERENCE DATE/TIME (recording metadata, not spoken words):\n";
    message += `referenceDateTime: ${referenceDateTime}\n`;
    message += `timeZone: ${timeZone}\n\n`;
  }
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
- Capture mood when the user directly describes their current mood, feeling, happiness, or emotional state. Qualitative language such as "I'm doing well" may be approximated to the closest reasonable score.
- Do not infer mood merely because a positive or negative event happened.
- If several current mood statements appear, use the latest clear self-report in transcript order.

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
- For event types, provide calendarCandidate whenever the words identify a date, a relative day, or a clock time.
  - suggestedTitle, startISO8601, endISO8601, isAllDay, notes
- Resolve "today", "tomorrow", weekdays, and other relative dates from the supplied REFERENCE DATE/TIME in its supplied TIME ZONE.
- If an event gives a clock time but no date, use the local calendar day of the reference date/time.
- If an event gives a date but no clock time, use yyyy-MM-dd for startISO8601, set endISO8601 to null, and isAllDay to false. This means "time not specified," not all-day.
- If neither a date nor clock time is stated or strongly implied, calendarCandidate may be null.

DAILY MOOD:
- moodLabel: one word or a short phrase describing the user's current feeling, or null.
- moodScore: the closest reasonable integer from 0 to 10, where 0 is lowest, 5 is neutral, and 10 is highest, or null.
- Capture mood only when the user directly describes their own current mood, feeling, happiness, or emotional state. A qualitative statement such as "I'm doing well" may be approximated.
- Do not infer mood merely because a positive or negative event happened.
- If the transcript contains multiple current mood statements, use the latest clear self-report in transcript order.
- Prior context can clarify the current transcript, but must not replace a newer mood stated in the current transcript.

Return ONLY valid JSON matching the schema. No markdown, no explanations.
If nothing meets the quality bar, return: {"items": [], "moodLabel": null, "moodScore": null}`;

const INTENTION_SUGGESTION_SYSTEM_PROMPT = `Create at most one fully custom, measurable micro-intention from the user's repeated evidence and current context. There is no action catalog. Transform the underlying need into a useful next behavior instead of parroting the topic or the user's stated goal.

QUALITY BAR:
- Make it specific, low-friction, and realistic enough to begin now.
- Prefer established behavior-design ideas: reduce activation energy, shape the environment, attach a small action to an existing cue, use retrieval practice, or create a concrete observation loop.
- Personalize only from supplied facts. Never infer diagnoses, personality, emotion, finances, relationships, abilities, or constraints that were not stated.
- Do not duplicate an active intention, an avoidExactFingerprint, or a close variation of avoidCloseVariantsOf. A different action in the same broad family is allowed only when it is meaningfully different.
- Use one supported unit: pages, minutes, sessions, steps, reps, cups, glasses, or times. Use daily or weekly.
- actionFingerprint is a stable lowercase snake_case description of the actual behavior, not the broad topic. actionFamily is one of movement, planning, learning, connection, finance_organization, sleep_routine, environment, creativity, reflection, or other.

RAPID TEST MODE:
When rapidTestMode is true, this is a developer evaluation harness. Prefer returning a useful suggestion whenever the supplied evidence supports any safe, genuinely new micro-action. Do not relax the evidence, active-intention duplicate, declined-action, or safety rules.

SAFETY:
Return the all-null form when the connection is weak, an existing intention already covers it, or the evidence involves injury, pain, pregnancy, medication, eating disorders, acute symptoms, crisis, debt strategy, investing, or individualized medical, legal, or financial guidance. Never diagnose, prescribe, recommend calorie restriction, promise outcomes, or tell the user to replace professional care.

The reason must be specific to the repeated evidence, under 140 characters, lightly clever when natural, professional, and never mocking. Cite one or more supplied evidenceItemIds. Return JSON only.`;

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
      moodLabel: { type: ["string", "null"] },
      moodScore: { type: ["integer", "null"] },
    },
    required: ["items", "moodLabel", "moodScore"],
    additionalProperties: false,
  },
};

const INTENTION_SUGGESTION_SCHEMA: ServerOwnedChatRequest["response_format"]["json_schema"] = {
  name: "intention_suggestion",
  strict: true,
  schema: {
    type: "object",
    properties: {
      title: { type: ["string", "null"] },
      targetValue: { type: ["number", "null"] },
      unit: { type: ["string", "null"], enum: ["pages", "minutes", "sessions", "steps", "reps", "cups", "glasses", "times", null] },
      timeframe: { type: ["string", "null"], enum: ["daily", "weekly", null] },
      reason: { type: ["string", "null"] },
      actionFingerprint: { type: ["string", "null"] },
      actionFamily: {
        type: ["string", "null"],
        enum: ["movement", "planning", "learning", "connection", "finance_organization", "sleep_routine", "environment", "creativity", "reflection", "other", null],
      },
      evidenceItemIds: { type: "array", items: { type: "string" } },
    },
    required: ["title", "targetValue", "unit", "timeframe", "reason", "actionFingerprint", "actionFamily", "evidenceItemIds"],
    additionalProperties: false,
  },
};
