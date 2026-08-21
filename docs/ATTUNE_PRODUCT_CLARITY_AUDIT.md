# Attune Product Clarity + Implementation Audit

**Audit date:** August 17, 2026

**Repository state audited:** current working tree on `wip/pre-appstore-changes`

**Scope:** product/architecture audit only; no production code changes are part of this document

## Executive summary

Attune does not need a major rewrite to support the proposed direction. The current app already contains most of the difficult foundations:

- a short Voice Check-In pipeline that persists transcripts and applies progress and mood updates;
- a separate, longer Talk it out pipeline that transcribes sessions, extracts events/intentions/commitments/states, preserves source quotes, groups recurring themes, and supports correction overlays;
- durable intention, progress, mood, check-in, session, extraction, correction, and topic stores;
- date-aware progress calculation, daily/weekly Momentum, check-in history, and intention detail views;
- deterministic, correction-aware session recaps;
- StoreKit 2 entitlement state and centralized Free/Pro access rules;
- DEBUG-only subscription switching and simulator Momentum demo data.

The largest product-clarity problem is that these capabilities are presented as separate features. The onboarding explains mechanics, Home leads with a utility-style Quick Check-In, Talk it out explains extraction, Insights shows organized memory, and Momentum shows progress—but the UI does not consistently connect them into one story:

> Talk → Understand → Act → See progress

The safest direction is therefore to build a thin, read-only product-understanding layer over the existing stores. It should reorganize and explain existing facts before expanding extraction contracts or persistence.

The most important technical constraint is that the two recording modes currently understand different things:

- **Quick Check-In** extracts only explicit progress against an existing measurable intention and optional mood.
- **Talk it out** extracts broader events, intentions, commitments, and states and groups related captures over time.

The desired example result—proposal finished, website deadline, exercise intention, and recurring work stress—from one Check-In cannot be produced truthfully by the present Check-In contract. A safer launch implementation should make the current Check-In result much clearer without claiming it captured broader facts. If product testing later shows that broad extraction must happen in Quick Check-In, that should be a separately designed medium feature with an additive contract, not a UI-only change and not an attempt to write Talk it out items into the progress system.

## Product principles for implementation

1. **One product story, two recording purposes.** Check-In updates what the user is actively tracking; Talk it out captures broader context the user does not want to lose.
2. **Derived before generated.** Daily and weekly briefs should begin as deterministic, local, correction-aware summaries. An AI-written narrative is optional later.
3. **No new source of truth.** Briefs should read existing stores. They should not create duplicate progress, completion, theme, or intention records.
4. **Truth over fluency.** Do not say something was completed, neglected, important, or causally related unless current data supports that statement.
5. **User ownership remains explicit.** Attune may detect, summarize, and suggest; it should not create or change an intention without a user tap and review.
6. **Cold start is a valid state.** With little data, show one useful next action rather than an empty analysis card.
7. **The Home hierarchy stays small.** Home should contain the next useful action, current intentions/progress, and at most one concise context/brief card—not a feed of every available metric.

---

# A. Current-state mapping

## A1. App shell, first run, and navigation

### Relevant UI and files

- `Attune/Attune/App/ContentView.swift`
  - Runs the branded launch intro.
  - Presents onboarding once using `AttuneOnboardingState`.
  - Presents the separate, required AI/privacy disclosure after onboarding.
- `Attune/Attune/UI/OnboardingView.swift`
  - Three benefit-led pages: Voice Check-Ins, Talk it out, and Momentum.
  - Uses static icons and explanatory copy; it does not visually demonstrate an input becoming organized output.
- `Attune/Attune/UI/AIPrivacyDisclosureSheet.swift`
  - Independent consent step; this separation should remain intact.
- `Attune/Attune/App/RootTabView.swift`
  - Root tabs: Today, Talk, Insights, Momentum.
  - Shared Attune header and Settings entry.
  - Applies subscription gates around Talk, Insights, and Momentum history.
- `Attune/Attune/App/AppRouter.swift`
  - Coordinates root-tab navigation and Momentum date routing.

### What exists and can be reused

- A small, already-built onboarding system is sufficient. A new onboarding framework is not needed.
- The current three-page structure maps naturally to the product loop:
  1. Talk naturally.
  2. See what Attune understood and remembered.
  3. Follow through and see change over time.
- The separate privacy disclosure prevents benefit copy from being mixed with consent language.
- Existing app navigation already separates the four major product surfaces.

### Current clarity issue

The first onboarding page starts with the data-model concept of a measurable intention and detailed Voice Check-In mechanics. The second page explains Talk it out and suggested next steps. The third sells Momentum and Pro. A new user can understand individual features but may still describe the product as a progress tracker or voice journal. Static symbols also make the “organizes and remembers” claim abstract.

### Safe recommendation

Keep three pages, but make them a visual transformation:

1. **Talk about what is going on** — show a short example speech bubble/waveform.
2. **Attune finds what matters** — animate or reveal 2–3 example cards such as a win, a follow-through item, and a recurring theme. These are illustrative, not live extraction.
3. **Pick up where you left off** — show an intention/progress card plus a concise “where you left off” example.

No persistence or backend change is needed. Avoid adding a permissions request to onboarding; permissions should stay contextual when the user taps a recording action.

## A2. Quick Check-In (“Talk about today”)

### Relevant UI and files

- `Attune/Attune/UI/Home/HomeView.swift`
  - Owns Quick Check-In recording state, permissions, transcription, extraction, ambiguity handling, persistence, receipt text, Today progress, mood, streak, and Momentum summary.
  - The idle card is labeled “Quick Check-In” and “Update progress or mood by voice.”
  - The saved state shows a compact receipt assembled by `checkInReceiptText(checkInId:)`.
- `Attune/Attune/Audio/CheckInRecorderService.swift`
  - Short recording capture.
- `Attune/Attune/Audio/TranscriptionWorker.swift`
  - Apple Speech transcription used by the recording flows.
- `Attune/Attune/UI/CheckIns/CheckInDetailView.swift`
  - Displays timestamp, transcript, persisted progress entries, optional mood, evidence, and cumulative percentages.
- `Attune/Attune/UI/CheckIns/CheckInsListView.swift`
  - Lists saved Check-Ins.
- `Attune/Attune/UI/Home/AmbiguityDisambiguationSheet.swift`
  - Resolves updates that could mean an increment or an absolute total.

### Models and stores

- `Models/CheckIn.swift` / `Storage/CheckInStore.swift`
  - Persist transcript, date, active `IntentionSet` ID, and optional audio filename.
- `Models/CheckInUpdate.swift`
  - Extraction result: intention ID, `INCREMENT` or `TOTAL`, amount, unit, confidence, evidence, and optional local occurrence time.
- `Models/ProgressEntry.swift` / `Storage/ProgressStore.swift`
  - Persist applied progress with `sourceCheckInId` provenance and `effectiveTookPlaceAt` chronology.
- `Models/DailyMood.swift` / `Storage/DailyMoodStore.swift`
  - One mood record per local day, with Check-In provenance or manual-override state.
- `Models/ManualProgressOverride.swift` / `Storage/OverrideStore.swift`
  - User-authored daily total overrides.
- `Understanding/ProgressCalculator.swift`
  - Source of truth for applying chronological `INCREMENT`/`TOTAL` rules and calculating progress.
- `Understanding/AmbiguityChecker.swift`
  - Protects progress from uncertain update interpretation.
- `Understanding/CheckInFallbackParser.swift`
  - DEBUG fallback behavior when AI returns no updates; it does not broaden the production data model.

### Services and backend

- `AI/CheckInExtractorService.swift`
  - Sends transcript, current intentions, aliases/targets/units/timeframes, and today’s totals.
- `AI/OpenAIClient.swift`
  - Routes through the Cloudflare proxy and retains v1 fallback behavior according to build configuration.
- `backend/openai-proxy/src/tasks.ts`
  - `/v2/check-ins/extract` owns the current server-side Check-In prompt/schema.
  - Contract returns `updates`, `moodLabel`, and `moodScore` only.
- `backend/openai-proxy/src/handler.ts`
  - Handles v1 compatibility, v2 task routing, usage accounting, and response validation.

### What the extractor actually produces

The Check-In extractor does **not** currently produce general accomplishments, deadlines, new candidate intentions, recurring patterns, or free-form observations. It only:

- maps explicitly stated progress to one of the supplied existing intentions;
- distinguishes increment from total;
- extracts evidence and optional occurrence time;
- extracts an optional mood label/score.

The current UI already has useful information that is under-presented:

- the exact intention title;
- amount and unit;
- increment versus total semantics;
- evidence quote;
- changed progress percentage;
- mood;
- the saved transcript;
- an ambiguity-confirmation step when meaning is uncertain.

The immediate receipt only presents up to two progress updates plus mood in a single sentence. It does not visually show “what changed,” link to the detailed receipt, or show before/after progress.

### Safe recommendation

For the first implementation, reorganize the existing saved result into a compact **“Attune picked up”** receipt with truthful rows:

- `Progress updated` — Launch website, +1 session (or total)
- `Now at` — 2 of 3 this week / percentage
- `Mood noted` — Focused, 7/10
- `No tracked change found` — with a short explanation and access to the transcript

Each row must be derived from persisted `ProgressEntry`/`DailyMood`, not from the transient model response. Include a “Review details” route to `CheckInDetailView`. This is a presentation and small derivation change.

Do not show proposal completion, a deadline, or a stress pattern from the sample input unless the extraction contract has separately been expanded and the new facts have a defined, correction-aware persistence destination.

## A3. Talk it out / proposed “Record Anything”

### Relevant UI and files

- `Attune/Attune/UI/Home/HomeRecordView.swift`
  - Current consumer label: “Talk it out.”
  - Explains: “Think out loud, clear your head, and notice what keeps coming up.”
  - Offers example prompts, recording/processing states, today’s session/capture counts, session history, capture history, completion feedback, deterministic recap previews, and intention-suggestion review.
- `Attune/Attune/Audio/RecorderService.swift`
  - Creates longer sessions and timed segments.
- `Attune/Attune/Audio/TranscriptionQueue.swift` and `TranscriptionWorker.swift`
  - Queue and persist segment transcription.
- `Attune/Attune/Understanding/ExtractionQueue.swift`
  - Runs extraction after persisted transcription and coordinates completion.
- `Attune/Attune/Understanding/ExtractorService.swift`
  - Calls the listening extraction task, supplies prior segment context, validates/canonicalizes/deduplicates items, persists them, and updates topics.
- `Attune/Attune/UI/Library/SessionRecapView.swift`
  - Deterministic session highlight and recap surfaces.
- `Attune/Attune/Understanding/SessionRecapBuilder.swift`
  - Correction-aware, read-only session recap with recurring-topic, commitment-count, or neutral fallback headlines.

### Models and stores

- `Models/Session.swift`, `Models/Segment.swift`, `Storage/SessionStore.swift`
  - Session/segment lifecycle, transcript state, and launch recovery.
- `Models/ExtractedItem.swift`, `Storage/ExtractionStore.swift`
  - Persist events, intentions, commitments, and states with summary, categories, confidence, strength, exact source quote, context, fingerprint, review state, and optional calendar candidate.
- `Models/ItemCorrection.swift`, `Storage/CorrectionsStore.swift`
  - Separate overlay for incorrect status, corrected title/type/categories, note, and calendar scheduling override. Original AI output remains unchanged.
- `Models/TopicAggregate.swift`, `Storage/TopicAggregateStore.swift`
  - Groups captures by a deterministic topic key and tracks linked item IDs.
- `Storage/ItemResolver.swift`
  - Resolves aggregate item IDs back to saved extractions.
- `Understanding/Canonicalizer.swift`, `TypeClassifier.swift`, `StrengthScorer.swift`, `TopicKeyBuilder.swift`, and `NormalizationRules.swift`
  - Existing normalization, type, importance heuristic, and topic-grouping stack.
- `Understanding/IntentionSuggestionEngine.swift`, `AI/IntentionSuggestionService.swift`, and `Storage/IntentionSuggestionStore.swift`
  - Uses repeated, eligible, correction-aware evidence to propose at most one editable micro-intention; it never silently adds it.

### Backend

- `/v2/listening/extract` in `backend/openai-proxy/src/tasks.ts`
  - Returns sparse high-confidence items with one of four allowed types.
  - Does not write progress.
- `/v2/intentions/suggest-action`
  - Produces a reviewed, measurable suggestion from repeated evidence with duplicate and safety checks.

### Safe recommendation

The behavioral distinction already exists and should mostly be communicated through copy and hierarchy:

- **Check-In:** “Talk about today. Update what you are tracking and note how you feel.”
- **Talk it out / Record Anything:** “Capture something you do not want to lose. Attune organizes useful details and notices what repeats.”

“Record Anything” is clear as a functional label but risks sounding like a generic audio recorder. “Talk it out” better conveys the emotional/use-case invitation. A low-risk compromise is:

- Tab label: **Record**
- Screen title: **Talk it out**
- Supporting line: **Capture something you don’t want to lose.**

No separate backend behavior is needed. Preserve the existing longer-session queue and extraction semantics.

## A4. Home / “What matters to me right now?”

### Relevant files and current hierarchy

- `UI/Home/HomeView.swift`
  - Current visible order:
    1. Quick Check-In card
    2. Today’s intentions/progress card
    3. Mood and streak card
    4. weekly Momentum for Pro or today-only Momentum for Free
    5. optional suggested-intention area
  - A `dailySummaryStrip` implementation exists but is not currently placed in the body.
  - Also includes One Thing mode, manual progress editing, progress highlighting, reminder refresh, review-prompt triggering, and suggested intention handling.
- `UI/Home/HomeStyle.swift`
  - Shared Home card styling, including the intention card’s distinctive glass/texture treatment.
- `Models/OneThingMode.swift`, `Storage/OneThingModeStore.swift`
  - Existing focused-intention state.
- `Understanding/WeekMomentumCalculator.swift`, `Models/WeekMomentum.swift`
  - Current week’s deterministic progress summary.
- `App/DailyReminderNotificationService.swift`
  - Existing daily notification decision based on today’s Check-In/progress state. It is not a daily brief generator.

### What can be reused

- Active intention order, percent, total, target, unit, timeframe, and recent dates.
- One Thing mode when the user wants a single focus.
- Yesterday/current-week progress via existing stores and calculators.
- Check-In completion and listening-processing notifications for refresh.
- Current card styles and existing `HomeView.refreshAll()` orchestration.

### Current clarity issue

Home is not a random analytics dashboard, but it reads as a stack of controls and metrics. It answers “what can I do here?” better than “what matters now?” It has no yesterday context and does not visibly connect broader memories from Talk it out to current follow-through.

### Safe recommendation

Use a maximum of three primary blocks:

1. **Today / Where you left off** — deterministic brief or cold-start prompt.
2. **What you’re moving forward** — active intentions, one focused item first, concise recent activity.
3. **Talk about today** — prominent Check-In action with a clear post-recording result.

Momentum can remain a compact supporting card/link. Mood and streak should be secondary details inside the Today context or progress block rather than a peer-level product pillar. Suggested intentions should remain event-driven and dismissible, not occupy permanent Home space.

The exact order should be tested. A sensible first version puts the daily brief first only when it has meaningful content; otherwise the Check-In action leads.

## A5. Daily brief

### Existing data that can generate it

- Yesterday’s active intention set(s): `IntentionSetStore` and date-aware helpers in `ProgressDataHelper`.
- Effective progress: `ProgressStore`, `OverrideStore`, and `ProgressCalculator`.
- Check-In evidence and mood: `CheckInStore`, `DailyMoodStore`.
- Completed processing sessions: `SessionStore`.
- Corrected captures and source quotes: `ExtractionStore`, `CorrectionsStore`.
- Repeated themes: `TopicAggregateStore` plus `ItemResolver` and unique parent-session resolution.
- Current active intentions and targets: `IntentionStore`, `IntentionSetStore`.

### What is not currently modeled

- There is no `DailyBrief` model/store.
- There is no general completion state for an extracted commitment or intention.
- Talk it out captures are not automatically linked to tracked `Intention` IDs.
- There is no cross-pipeline fact graph proving that “pricing page finished” advanced “launch website.”
- There is no first-open-of-day dismissal/revisit state.

### Recommended v1 design

Create a pure, read-only `DailyBriefBuilder` (name illustrative) that returns display sections, not a persisted life-summary record. It should use conservative facts such as:

- “Yesterday you added 20 minutes to Walk.”
- “You are at 2 of 3 Workout sessions this week.”
- “You mentioned Website launch in a Talk it out session yesterday.”
- “No progress was recorded yesterday. Pick one thing to move forward today.”

Do not infer a causal connection between captures and progress. Do not say “you are getting close” unless a tracked intention has a valid target and effective total that supports that statement.

Use deterministic sentence templates initially. This requires no backend and no AI call. It is easier to test, costs nothing, works offline, and is auditable against the underlying records.

### Display lifecycle

- Place the card at the top of Home when it has useful content.
- Make it collapsible/dismissible for the local date.
- Persist only presentation state such as `lastDismissedDateKey` in `UserDefaults` or a tiny additive preference—not the brief’s factual output.
- Keep a small “Today brief” affordance so the user can revisit it.
- Recompute when relevant persisted data changes or the app enters the foreground on a new local day.
- Use time-neutral copy (“Where you left off”) unless greeting is selected from the current local hour.

### Cold start and low-data behavior

- No intentions and no sessions: explain the loop in one sentence and offer Check-In or Talk it out.
- Intentions but no yesterday activity: show the current intention and one Check-In prompt.
- Talk it out history but no tracked intentions: show one recent corrected capture/theme and invite the user to review it; do not silently create an intention.
- Only today’s data: use a Today status, not a fake yesterday recap.
- Processing session exists: omit it until extraction is fully persisted; refresh after completion.

## A6. Weekly brief

### Existing reusable architecture

- Progress by day and intention: `ProgressDataHelper`, `ProgressCalculator`, `WeekMomentumCalculator`.
- Intention target/timeframe and historical sets: `Intention`, `IntentionSet`, their stores.
- Check-In and mood chronology: `CheckInStore`, `DailyMoodStore`.
- Corrected captures: `ExtractionStore` plus `ItemCorrection` overlay.
- Topic membership and dates: `TopicAggregateStore`, `ItemResolver`, `SessionStore`.
- Conservative recap precedent: `SessionRecapBuilder`.

The architecture is close to supporting a useful deterministic weekly review. It is **not** yet able to truthfully provide every desired narrative claim.

### Truthfully derivable now

- progress totals/percentages by day and week;
- days with activity;
- tracked intentions that advanced or reached their numeric target;
- Check-In frequency;
- mood values when present;
- corrected captures created during the week;
- themes mentioned in multiple distinct sessions during the week;
- direct, source-backed commitments or intentions the user said.

### Not safely derivable without new semantics

- whether a free-form commitment was completed;
- whether something is “slipping” versus intentionally paused;
- which life event was objectively most important;
- whether two differently worded captures caused one another;
- whether a stored `reviewState` value means active product completion.

`TopicAggregate.occurrenceCount` counts item mentions, not distinct sessions. Weekly recurrence must resolve item IDs to parent sessions and count unique eligible session IDs. Corrections marked `isIncorrect` must be excluded. Title/category corrections can make stored topic grouping stale; a weekly builder should follow the conservative behavior already used by `SessionRecapBuilder` and avoid unsupported recurring-theme claims.

### Recommended v1 design

Implement a deterministic, read-only weekly brief with 3–4 bounded sections:

1. **Moved forward** — tracked intentions with factual progress.
2. **Worth remembering** — selected corrected captures with source-backed language.
3. **Kept coming up** — themes present in at least two distinct eligible sessions.
4. **Going into next week** — current active intention or a user-reviewed suggestion, never an auto-created task.

Avoid “neglected”/“slipping” in v1. A neutral phrase such as “No progress recorded this week” is factual but should be presented without judgment.

An AI-written weekly narrative can be evaluated later using the deterministic fact packet as its only input. The deterministic fact packet and UI should remain the source of truth even if narrative generation is added.

## A7. Intentions

### Relevant files

- `Models/Intention.swift`
  - Stable ID, title, target, unit, daily/weekly timeframe, category, active state, creation date, aliases.
- `Models/IntentionSet.swift`
  - Defines which intentions were active during a time span.
- `Storage/IntentionStore.swift`, `Storage/IntentionSetStore.swift`
  - File-based persistence and current/historical sets.
- `UI/Home/EditIntentionsView.swift`
  - Add/edit/delete/review workflow, Free/Pro limits, voice setup, and safe suggestion replacement.
- `UI/Home/AddEditIntentionView.swift`
  - Additional intention editing/setup UI.
- `AI/IntentionsParserService.swift`, `/v2/intentions/parse`
  - Converts voice setup into reviewed measurable drafts.
- `UI/Progress/IntentionDetailView.swift`
  - Target plus last seven days of totals/percentages.
- `UI/Progress/IntentionDetailRouteView.swift`, `ProgressDataHelper.swift`
  - Date-aware detail routing and read model.
- `Understanding/IntentionSuggestionEngine.swift`
  - Proposes an editable next step from repeated evidence with duplicate/safety controls.

### Current clarity issue

The storage is suitable, but the consumer experience emphasizes configuration: numeric target, unit, timeframe, percent, and editing. The detail view is a table of the last seven days rather than a living view of recent activity and why the intention matters now.

### Safe recommendation

- Keep the persisted `Intention` model unchanged initially.
- Describe intentions as “what you’re moving forward,” while retaining “Intention” where needed for consistency.
- Add a short recent-activity line derived from existing entries: last update, this-week total, or “No update yet this week.”
- Link relevant Check-In evidence through `sourceCheckInId` when the user asks for detail.
- Show a weekly target as a weekly total, not merely a daily target divided by seven in consumer copy.
- Use daily/weekly brief surfaces to provide context; do not persist narrative fields onto `Intention` yet.
- Preserve the explicit review/save step for voice-created or suggested intentions.

## A8. Library / Insights

### Relevant files and current content

- `UI/Library/LibraryView.swift`
  - Header: “Insights — What you’ve said—and what keeps coming up.”
  - Summary metrics for captured items, recurring themes, and sessions.
  - Featured themes, recent captures, history links for sessions and Voice Check-Ins, and DEBUG calendar entry.
- `UI/Library/InsightsListView.swift`
  - Captures/Themes segmented list, filters, search, corrected display.
- `UI/Library/InsightDetailView.swift`
  - Capture summary, source evidence, and correction/review controls.
- `UI/Library/TopicDetailView.swift`
  - Theme occurrences with correction-aware filtering and an explanation that themes do not alter progress or create intentions.
- `UI/Library/SessionListView.swift`, `SessionDetailView.swift`
  - Long-session history, recap, transcript, and visible captures.
- `UI/CheckIns/CheckInsListView.swift`, `CheckInDetailView.swift`
  - Quick Check-In history and detail.

### Current clarity issue

The implementation is already more than a list of recordings. It contains corrected captures, recurring themes, searchable lists, source quotes, both kinds of recording history, and session recaps. The remaining problem is naming and hierarchy: “Insights” sounds analytical, while “History” splits sessions and Check-Ins without presenting them as one memory system.

### Minimum useful change

- Retain the existing architecture and screens.
- Consider the tab/screen concept **Memory** or **What Attune remembers**, while keeping “Insights” as a subsection if preferred.
- Lead with recent meaningful captures and recurring themes; reduce the prominence of raw count metrics if they do not help a user decide what to review.
- Keep Sessions and Check-Ins as source/history filters, not separate product concepts.
- Add one explanatory line: “Everything Attune remembers stays tied to what you said and can be corrected.”

Do not build a document system, tags, folders, backlinks, or a new search index for launch.

## A9. Pro / subscription positioning

### Relevant files and current behavior

- `UI/Settings/PaywallView.swift`
  - Hero: “Track more, see the patterns, and keep your full progress history.”
  - Benefits: more intentions, Voice Check-Ins, Talk it out with Insights, full Momentum history, voice setup/data export.
  - Also emphasizes a monthly AI processing allowance.
- `App/SubscriptionConfig.swift`
  - Monthly product ID remains `com.scottoliver.Attune.monthly`.
  - Free: one Check-In/day and one active intention.
  - Maximum active intentions: ten.
- `App/SubscriptionAccessPolicy.swift`
  - Central rules for Check-In count, Talk it out, voice intentions, Insights, Momentum history, export, and intention count.
- `App/SubscriptionManager.swift`
  - StoreKit 2 product/entitlement state and DEBUG Free/Pro/System switching.
- `UI/Settings/SubscriptionAccessViews.swift`
  - Locked-feature and free Momentum surfaces.

### Current positioning assessment

The paywall has already moved beyond “more recordings.” Its best language is history and patterns. However, individual benefit rows still read as a feature inventory, and the monthly AI allowance line foregrounds cost mechanics instead of durable user value.

### Safe recommendation

Position Pro as continuity:

> Attune Pro keeps the full picture—more of what you are working on, what you have said, and how it changes over time.

Suggested grouping using existing entitlements:

- **Free:** one active intention, one daily Check-In, today’s progress/Momentum, daily reminder, and a useful deterministic daily status based only on Free-access data.
- **Pro:** up to ten active intentions, unlimited Check-Ins within the server allowance, Talk it out, corrected/searchable memory, recurring themes, full Momentum history, export, and the richer weekly review.

Daily brief should not be marketed as valuable only because it uses AI; the deterministic form does not require an AI call. A basic daily status is valuable for Free activation and demonstrates the core loop. A richer cross-session weekly brief logically fits Pro because its source data (Talk it out/Insights/history) is already Pro-gated.

Do not change product ID, price, StoreKit configuration, or entitlement logic during copy work. Internal `Attune` storage paths and product identifiers do not need renaming for product clarity and should remain stable.

---

# B. Gap analysis

| Area | Classification | Why |
|---|---|---|
| Onboarding clarity | Mostly copy / UI | Three-page first-run system already exists. It needs a clearer loop and a visual input→understanding→follow-through example, not new persistence. |
| Check-In result clarity | Small logic change | Persisted progress/mood/evidence already exists; a structured receipt needs derivation and navigation. The broader sample result would be a separate medium contract/persistence feature and should not be implied by this phase. |
| Check-In vs Record Anything distinction | Mostly copy / UI | Pipelines are already behaviorally distinct. Labels, subtitles, and examples can explain them without backend changes. |
| Home / “what matters now” | Medium feature | Reordering is easy, but a reliable read model must combine date-aware progress, current intentions, optional captures, and refresh/dismissal behavior without duplicating truth. |
| Daily brief | Medium feature | Existing data is sufficient for a conservative deterministic brief, but a new read-only builder, cold-start policy, day-boundary handling, and presentation state are needed. |
| Weekly brief | Medium feature | Aggregates and chronology exist, but recurrence must count unique sessions and all claims must be correction-aware. Completion/neglect semantics should remain out of scope. |
| Intentions clarity | Small logic change | Naming/copy is easy; recent activity and weekly rollups can be derived using current entries and calculators. No model rewrite is needed. |
| Library clarity | Mostly copy / UI | The current Insights UI already contains captures, themes, search, corrections, sessions, and Check-Ins. Reframe it as memory and simplify hierarchy. |
| Pro positioning | Mostly copy / UI | Central entitlement logic already exists. Copy and grouping can emphasize continuity; any new brief gate requires policy tests but not a StoreKit redesign. |

## Important scope split for Check-In

There are two different possible projects hidden under “Check-In result clarity”:

1. **Truthfully present current output** — small, low-risk, recommended before launch.
2. **Make Check-In also extract general wins, deadlines, candidate intentions, and patterns** — medium-to-high risk because it needs an additive backend schema, a persistence destination, correction UI, deduplication rules, usage review, and clear separation from Talk it out.

Do not let the first project silently become the second.

---

# C. Difficulty + risk table

| Proposed area | User value | Difficulty | Regression risk | Backend changes | AI call required | Existing architecture reusable |
|---|---|---|---|---|---|---|
| Reframe onboarding around Talk→Understand→Act→Progress | Very High | Low | Low | No | No | High |
| Add illustrative onboarding transformation | High | Low | Low | No | No | High |
| Structured persisted Check-In receipt | Very High | Low–Medium | Medium | No | No additional call | High |
| Expand Check-In to broad life extraction | High | High | High | Yes | Yes | Medium |
| Clarify Check-In vs Talk it out/Record | High | Low | Low | No | No | High |
| Simplify Home hierarchy | Very High | Medium | Medium | No | No | High |
| Add recent activity to intention cards/details | High | Low–Medium | Medium | No | No | High |
| Deterministic daily brief | Very High | Medium | Medium | No | No | High |
| AI-written daily narrative | Medium | Medium–High | Medium–High | Maybe | Yes | Medium |
| Deterministic weekly brief | High | Medium | Medium | No | No | High |
| AI-written weekly narrative from fact packet | Medium | High | Medium–High | Maybe | Yes | Medium |
| Reframe Library as memory | High | Low | Low | No | No | High |
| Reposition Pro around continuity | High | Low | Low–Medium | No | No | High |
| Add a new daily/weekly entitlement | Medium | Low–Medium | Medium | No | No | High |

“No backend changes” assumes deterministic read models built from local persisted data. If product requires server-synced briefs, generated narratives, or broadened Check-In extraction, the assessment changes.

---

# D. Safest implementation order

Each phase should be independently reviewable and reversible. Avoid combining product-language changes with extraction contracts or StoreKit behavior.

## Phase 0 — Characterization and read-model tests

**Purpose:** lock down current semantics before rearranging UI.

Suggested commit:

- Add pure test fixtures for `INCREMENT`/`TOTAL`, overrides, weekly intentions, set boundaries, corrections, distinct-session topic counts, and incomplete sessions.
- If a shared brief fact builder is introduced later, start with its test matrix and no UI.

No shipping UI change is required in this phase.

## Phase 1 — Product language and onboarding

**Purpose:** make the value proposition understandable without changing behavior.

Suggested commits:

1. Rewrite the existing three onboarding pages around the product loop.
2. Add a restrained, static/short visual example of speech becoming organized facts and progress.
3. Clarify tab/screen labels and supporting copy for Check-In versus Talk it out/Record.
4. Reframe Library header/empty state as what Attune remembers.

Keep AI privacy consent copy and sequencing separate.

## Phase 2 — Check-In understanding receipt

**Purpose:** make the existing intelligence visible immediately after persistence.

Suggested commits:

1. Extract a pure receipt read model from persisted `ProgressEntry`, `DailyMood`, `Intention`, and Check-In data.
2. Replace the one-line saved receipt with grouped rows and a details link.
3. Improve `CheckInDetailView` hierarchy using the same read model.
4. Add explicit “nothing tracked changed” and ambiguity-resolved states.

Do not broaden the extraction schema in this phase.

## Phase 3 — Home hierarchy and living intentions

**Purpose:** make Home answer “what matters now?” with fewer peer-level cards.

Suggested commits:

1. Reorder/merge existing Home cards without changing stores.
2. Add date-aware recent activity to each active intention using existing progress calculation.
3. Keep Momentum as a compact supporting route and fold mood/streak into secondary context.
4. Validate One Thing mode, suggestion presentation, review prompting, and Free/Pro variants after reordering.

## Phase 4 — Deterministic daily brief MVP

**Purpose:** deliver “where you left off and what matters today” without a new AI call.

Suggested commits:

1. Add a pure, correction-aware `DailyBriefBuilder` and tests.
2. Add cold-start/low-data policies.
3. Add Home presentation with local-date dismissal and revisit behavior.
4. Refresh only from persisted store/queue completion events and foreground/day changes.

Start with progress/current-intention facts. Add Talk it out facts only when entitlement and correction behavior are explicit.

## Phase 5 — Pro value presentation

**Purpose:** align the paywall with the product the user has just experienced.

Suggested commits:

1. Rewrite paywall hero and benefit grouping around continuity, memory, and follow-through.
2. Keep legal/payment terms and StoreKit behavior unchanged.
3. Add/adjust `SubscriptionAccessPolicyTests` only if a brief entitlement is introduced.

This can occur before or immediately after Phase 4, but the paywall should not promise an unimplemented brief.

## Phase 6 — Deterministic weekly brief

**Purpose:** answer “what changed this week?” using verified facts.

Suggested commits:

1. Build/test a weekly fact packet with effective progress, corrected captures, and unique-session themes.
2. Add a concise weekly review surface, preferably reachable from Home and revisitable from Insights/Memory or Momentum.
3. Add Free/Pro policy only after the product experience is settled.

This is a good post-launch candidate unless launch positioning explicitly promises weekly understanding.

## Phase 7 — Evaluate broader Check-In extraction or generated narrative

Only after usability evidence:

- Test whether users expect Quick Check-In to capture broader wins/deadlines/states.
- If yes, design an additive contract and explicit destination for those facts.
- Evaluate AI narrative against deterministic facts for incremental value, hallucination rate, latency, and usage cost.
- Keep deterministic output available as fallback.

---

# E. Architecture concerns and guardrails

## E1. Do not duplicate progress logic

- All daily/weekly totals must use `ProgressCalculator` and effective manual overrides.
- Preserve chronological `TOTAL` reset and subsequent `INCREMENT` behavior.
- Respect `effectiveTookPlaceAt`, not only file creation time.
- Weekly intentions need correct weekly totals in narrative. Do not casually use a daily `target / 7` approximation when describing the weekly goal.
- Do not calculate progress a second way inside SwiftUI views.

## E2. Preserve Check-In provenance

- `ProgressEntry.sourceCheckInId` must contain a real Check-In ID.
- A Talk it out `Session.id` is not interchangeable with a Check-In ID.
- A future bridge from Talk it out to progress needs an additive provenance design and user confirmation; it must not fake a Check-In.

## E3. Keep the two extraction systems separate

- Check-In schema: existing-intention progress + mood.
- Talk it out schema: event/intention/commitment/state captures.
- Do not run both pipelines against every short recording without a deliberate cost, latency, correction, and deduplication design.
- Do not automatically turn an extracted `ExtractedItem.ItemType.intention` into a tracked `Intention`; their meanings and storage are different.

## E4. Apply corrections everywhere a fact is surfaced

- Exclude `ItemCorrection.isIncorrect == true` from briefs and themes.
- Use corrected title/type/categories for display.
- Preserve original extraction and source quote.
- If a title/category correction invalidates stored topic membership, avoid a recurring-theme claim unless regrouping is explicitly rebuilt safely.
- Do not treat `reviewState == rejected` as the current consumer hidden/incorrect source of truth. The active correction overlay is `isIncorrect`; legacy/deprecated state semantics should not be revived accidentally.

## E5. Do not misuse topic counts

- `TopicAggregate.occurrenceCount` is a count of item mentions.
- “Across N sessions” requires resolving linked items and counting unique eligible parent `Session.id` values.
- Filter by the relevant calendar interval and only fully persisted sessions/items.
- Handle orphaned item IDs conservatively.

## E6. Avoid invented completion and neglect semantics

- Numeric target reached can be described as target reached for a tracked intention.
- A Talk it out commitment being mentioned does not mean it was completed.
- No progress record does not prove neglect, loss of interest, or failure.
- A recurring state does not prove a causal pattern.
- Prefer “mentioned,” “recorded,” “moved forward,” and “no progress recorded” over subjective interpretations.

## E7. Intention-set boundaries and historical data

- Editing intentions creates historical/current set boundaries. A daily/weekly builder must select the set active on each date rather than assume the current set describes yesterday.
- Preserve stable intention IDs where the existing editor does so.
- A removed/archived intention may still be relevant to a historical brief but should not be presented as an active next step.
- Never rewrite historical sets just to make brief generation easier.

## E8. Queue and race-condition safety

- A session can be recording, queued, transcribing, extracting, complete, or failed/recovering.
- Briefs should use only persisted facts; omit incomplete extraction rather than display transient model output.
- Refresh after `.attuneListeningSessionDidFinishProcessing`, successful Check-In persistence, scene foreground, and local day changes.
- Use snapshot-based pure builders off the rendering hot path. Avoid repeated full disk scans during each SwiftUI body evaluation.
- Tokenize/cancel delayed UI resets so old dismissal or refresh tasks cannot clear new state, following existing Home feedback patterns.

## E9. AI calls, usage, and offline behavior

- Daily/weekly deterministic summaries require no AI call and should work offline.
- A generated brief could consume significant monthly allowance, especially if run automatically on launch.
- Never run generation on every foreground event.
- If AI narrative is later added, cache by a deterministic input fingerprint/date, expose fallback, and do not charge repeated calls for unchanged facts.
- Do not promise generated understanding beyond the server’s usage allowance without a clear failure state.

## E10. Entitlement boundaries and privacy

- A Free daily brief can summarize Free-access intention/Check-In data.
- Do not leak Pro-gated Talk it out/Insights content through a Free Home brief after entitlement loss without an explicit product policy.
- Existing user data should never be deleted when entitlement expires.
- Local brief builders should not add remote analytics or upload new personal content.
- A brief preference may store date/dismissal state, not copied transcript text.

## E11. Migration and brand stability

- New presentation state should be additive and backward compatible.
- Do not migrate `Documents/Attune` paths, StoreKit IDs, or internal type names merely because the consumer name is Attune.
- Do not modify the existing monthly product ID, price, or StoreKit configuration during clarity work.
- Keep v1 fallback and independently controlled v2 routes until their established release-validation gates are satisfied.

## E12. Cold start and notification overlap

- The daily reminder is a notification policy, not a daily brief. Avoid presenting the same nag in both places.
- If the user has already checked in or made progress, the Home brief should acknowledge that rather than still demand a Check-In.
- Brand-new users should receive a useful action, not zero-value metrics or “no patterns yet” repeated across multiple cards.

---

# F. Testing plan

## Common test setup

Run both automated and physical-device checks. A simulator build proves compilation and store/read-model integration; it does not verify microphone levels, Speech permissions, transcription, haptics, StoreKit/TestFlight behavior, or physical visual feel.

Existing development aids to reuse:

- Settings → Developer → **Subscription Access**: Free / Pro / System in DEBUG.
- Simulator-only **Momentum demo data** controls, where available.
- Existing local Engagement Diagnostics for counts/dates only.
- Existing suggestion rapid-test flag only for suggestion evaluation; do not reuse it to change brief truth rules.

Recommended additive DEBUG-only aids for later implementation:

- Reset onboarding completion without deleting user data.
- Preview daily/weekly brief for a selected date using a read-only snapshot.
- Load/remove namespaced brief test fixtures with a manifest and verified cleanup, modeled after `MomentumDemoDataManager`.
- Force brief presentation state (new, dismissed, revisited) without changing production defaults.
- Display the exact factual inputs/claim reasons used by a deterministic brief.

All seed records should use reserved IDs, avoid production analytics, and have an auditable removal/verification path. Never ship seed controls in Release.

## Phase 1 — Onboarding and language

### New-user flow

1. Reset onboarding in a DEBUG build or install clean.
2. View all pages on a small iPhone and a current large iPhone.
3. Before interacting with the app, ask the tester: “What do you think the app will do for you?”
4. Expected answer should include organizing/remembering/follow-through, not only transcription or journaling.
5. Complete onboarding and confirm the separate AI privacy disclosure still appears and cannot be bypassed accidentally.

### Visual/accessibility checks

- Dynamic Type through accessibility sizes.
- VoiceOver reading order and meaningful labels for illustrative cards.
- Reduce Motion: transformation remains understandable without animation.
- No onboarding illustration should look like real extracted user content.

### Existing-user flow

- Confirm onboarding does not reappear after copy changes.
- Confirm Settings/About/locked screens use consistent labels.

## Phase 2 — Check-In receipt

Create active intentions such as:

- `Launch website` — 5 sessions weekly
- `Exercise` — 3 sessions weekly
- `Read` — 20 pages daily

### Physical iPhone phrases

1. **Increment + mood**

   “I worked on Launch website for one more session. My mood is seven out of ten and I feel focused.”

   Expected: one persisted increment linked to Launch website, optional mood, structured receipt, changed Home progress.

2. **Absolute total**

   “I have read twelve pages total today.”

   Expected: `TOTAL` semantics shown as total, not +12; detail evidence available.

3. **Multiple updates**

   “I exercised once more and worked on the website for two more sessions. Mood six out of ten.”

   Expected: all persisted rows represented or a clear “+N more” affordance; details show all.

4. **No tracked change**

   “Work was stressful and I finished a proposal.”

   Expected under the current contract: Check-In saved, no progress/mood change found. The UI must not claim proposal completion or a stress pattern was captured.

5. **Ambiguity**

   “I read ten pages.”

   Expected: ambiguity UI if current rules find increment versus total unclear; final receipt appears only after resolution and reflects persisted result.

6. **Alias**

   If Exercise has alias `workout`: “I did one workout.”

   Expected: maps to Exercise without creating a new intention.

### Empty/error tests

- No active intentions; mood-only phrase.
- No active intentions; non-mood phrase.
- Microphone denied.
- Speech recognition denied.
- Network unavailable after transcription.
- Monthly AI limit response.
- App backgrounded during processing and reopened.
- Failed extraction must not show a success claim.

### Existing-user regression

- Historical Check-In detail still loads.
- Manual override still wins according to current rules.
- `TOTAL` followed by later increment remains correct.
- Explicit occurrence time appears in the right chronology.
- Review-prompt trigger still occurs only after a real successful persisted Check-In under its current eligibility policy.

## Phase 3 — Home and intentions

### Data-state matrix

- No intentions, no activity.
- One Free intention, zero progress.
- One intention partially complete.
- Multiple Pro intentions with mixed progress.
- One Thing mode active and inactive.
- Daily and weekly intentions together.
- Historical intention set changed yesterday.
- Mood present/absent.
- Suggested intention pending/declined/accepted.

### Expected behavior

- The next useful action is visible without unnecessary scrolling.
- Current intentions are the primary status, not raw counts.
- Recent-activity copy matches effective persisted totals.
- A weekly intention is described in weekly terms.
- Editing, deleting, or swapping an intention refreshes Home after sheet dismissal.
- “Not for me” still suppresses the originating suggestion/theme according to existing rules.
- Reduce Motion and VoiceOver remain correct.

### Free/Pro checks

- DEBUG Free: one intention, one Check-In/day, today-only Momentum, Talk/Insights locked.
- DEBUG Pro: multiple intentions, Talk/Insights, full Momentum.
- DEBUG System: follows StoreKit test configuration.
- Downgraded user with multiple existing intentions can remove/edit safely but cannot add new IDs beyond policy; no data is deleted.

## Phase 4 — Daily brief

### Deterministic fixture cases

1. **Yesterday progress, current weekly goal**

   Yesterday: Exercise +1 session; week total 2 of 3.

   Expected: factual sentence stating yesterday’s update and current weekly total.

2. **`TOTAL` then increment**

   Yesterday total 10 pages, then +2 pages.

   Expected: 12 using `ProgressCalculator`, not 2 or 10.

3. **Manual override**

   Entries sum to 8, user overrides to 5.

   Expected: effective displayed value follows current override policy.

4. **Intention-set boundary**

   An intention was active yesterday but removed today.

   Expected: yesterday fact may be stated as history; it is not recommended as today’s active focus.

5. **Talk it out capture**

   Corrected capture from a completed session yesterday.

   Expected: “You mentioned…” with corrected title/source availability; no invented progress link.

6. **Incorrect capture**

   Same item marked incorrect.

   Expected: omitted from brief.

7. **Incomplete processing**

   Session transcribed but extraction not complete.

   Expected: omitted until persistence completion, then brief refreshes.

8. **No data/cold start**

   Expected: one action-oriented prompt, no empty metrics.

### Lifecycle checks

- First appropriate foreground on a new local date shows the brief when meaningful.
- Dismissal lasts for that date only.
- Revisit restores the same deterministic facts unless underlying data changed.
- Crossing midnight/time-zone change does not show the wrong day.
- Opening the app repeatedly does not reanimate or nag.
- Offline mode works.

## Phase 5 — Paywall

### Free-user checks

- Trigger from second intention.
- Trigger after free daily Check-In limit.
- Open locked Talk and Insights tabs.
- Confirm the reason-specific copy flows into the continuity-led paywall without contradiction.

### Pro/System checks

- StoreKit local configuration loads product and price.
- Subscribe, pending, cancel, restore, no-active-subscription, and unavailable-product states remain unchanged.
- Legal links and renewal language remain visible.
- Paywall promises only currently implemented features.
- Debug Pro is not treated as proof of a real Sandbox/TestFlight entitlement.

## Phase 6 — Weekly brief

### Fixture/test cases

1. Mixed daily and weekly intentions over seven days.
2. `TOTAL` and increments on the same day.
3. Intention-set changes midweek.
4. Two extracted items from one session versus one item in each of two sessions.
   - Expected: only the latter supports “across two sessions.”
5. Topic with an orphaned item ID.
   - Expected: conservative omission of recurrence claim.
6. Topic with an incorrect item.
   - Expected: incorrect occurrence excluded.
7. Topic with corrected title/category that invalidates grouping.
   - Expected: no unsupported stored-topic claim.
8. Mentioned commitment with no completion evidence.
   - Expected: “you said you’d…” or “worth remembering,” never “completed.”
9. No progress recorded.
   - Expected: neutral language, no “slipping” judgment.
10. Week crossing month/year and daylight-saving boundaries.

### User-flow checks

- Weekly brief is concise enough to scan.
- Every claim can navigate to or expose supporting progress/capture evidence.
- Revisit location is consistent.
- Free/Pro behavior matches tested access policy.
- Existing Momentum week/month charts remain unchanged unless deliberately linked.

## Phase 7 — Optional broader extraction / AI narrative evaluation

Use a controlled test set including the brief’s example:

> “Work was pretty stressful today. I finally finished that proposal though. I really need to start working out again, and I want to get the website launched by Friday.”

Before implementation, define expected destinations for each fact:

- proposal finished — accomplishment model or corrected capture?
- website by Friday — event, commitment, candidate intention, or more than one?
- exercise again — candidate intention requiring review?
- recurring work stress — state capture plus cross-session recurrence, only if supported by prior eligible sessions?

Evaluate:

- precision/false-positive rate;
- duplicates against Talk it out;
- correction path for every surfaced fact;
- latency and token cost;
- behavior with no existing intentions;
- whether users actually expect broad capture from the short mode;
- whether the benefit exceeds simply guiding users to Talk it out for broad capture.

Do not ship until each output has a stable, reversible persistence and correction story.

---

# G. Final recommendation

## 1. Three biggest understanding improvements for the least risk

### 1) Reframe onboarding as a visual product loop

Use the existing three pages to show talk → organized understanding → follow-through/progress. This is the highest leverage, lowest-risk way to prevent the “voice journal” interpretation.

### 2) Make the post-Check-In receipt visibly show what changed

The app already persists trustworthy progress, mood, and evidence. A structured “Attune picked up” result will make intelligence visible at the exact moment the user expects it, without changing extraction.

### 3) Clarify the two recording modes and simplify Home hierarchy

Use “Talk about today” for Check-In and “Capture something you don’t want to lose” for Talk it out/Record. Then organize Home around a concise where-you-left-off/current-intention/action hierarchy.

## 2. Changes to implement before App Store launch

Definitely before launch:

- onboarding language/visual transformation;
- consistent Check-In versus Talk it out/Record labels and examples;
- structured, persisted Check-In result with a truthful no-change state;
- Home hierarchy cleanup without new persistence;
- Library framing as memory rather than only recordings/analytics;
- paywall copy centered on continuity, memory, and follow-through, without changing StoreKit.

Strongly recommended before launch if schedule permits:

- a narrow deterministic daily “where you left off” MVP using only progress/current-intention facts;
- at minimum, the read-model tests and a compact Home context card, even if Talk it out facts are added later.

The daily brief is important because it demonstrates why the app becomes more valuable tomorrow. It should not delay launch for an AI narrative or cross-domain inference system.

## 3. Changes that should wait for real-user evidence

- Broadening Quick Check-In into general life extraction.
- AI-generated daily prose.
- AI-generated weekly prose.
- “Things slipping” or neglected-item judgments.
- Automatic relationships between Talk it out captures and tracked intentions.
- New completion state for free-form commitments.
- A large weekly analytics experience.
- A new cross-device/server brief database.

First test whether users understand and use the existing two-mode loop after the language, receipt, and Home improvements.

## 4. Ideas solving the wrong problem or adding unnecessary complexity

- **A new AI call for every daily open** solves wording, not product truth, while adding latency, cost, failure states, and hallucination risk. Start deterministic.
- **Making Check-In and Talk it out use the same backend behavior** would erase a useful distinction and create duplicate captures/progress ambiguity.
- **Treating every extracted intention as a tracked Intention** would remove user ownership and destabilize active-set/progress semantics.
- **A giant Home dashboard** would weaken the “what matters now” goal.
- **A full task manager, new calendar, chatbot, or knowledge-management system** is not required for this direction.
- **Renaming internal Attune storage paths/product IDs** would add migration and StoreKit risk without improving user understanding.
- **Calling lack of data neglect** would overstate what the app knows.

## 5. Is the architecture strong enough without a major rewrite?

**Yes.** The current architecture is strong enough for the proposed product direction if implementation remains a read-only, correction-aware presentation layer over existing stores.

The system is particularly well positioned because progress and broad memory are already separate, provenance is preserved, corrections are overlays rather than destructive edits, topics link back to source items, and session recaps demonstrate a conservative deterministic pattern.

The missing architectural piece is a small family of tested read models/builders that assemble existing facts for Check-In receipts, daily context, and weekly review. That is medium feature work, not a new backend or database.

A major change becomes necessary only if Attune must infer broader facts from every Quick Check-In, connect free-form speech to tracked progress automatically, sync generated briefs across devices, or persist new accomplishment/commitment lifecycle semantics. Those should be justified by observed user behavior, not assumed before launch.

## Recommended decision

Approve Phases 0–3 as the low-risk launch clarity package. Plan a narrow deterministic Daily Brief as Phase 4, with no new AI call and no Talk it out→progress inference. Reassess the broader Check-In example and Weekly Brief narrative after usability testing confirms which facts users expect Attune to remember and act on.
