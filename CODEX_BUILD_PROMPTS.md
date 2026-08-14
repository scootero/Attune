# Attune — Phased Build Prompts for Codex

Last updated: August 6, 2026

Four sequential enhancement phases. **Run each in its own Codex chat.** Do not
start one until the previous enhancement phase is verified on a physical iPhone.
Each is additive and independently revertable. These labels are intentionally
separate from the release/security phase numbers in `ATTUNE_REMAINING_WORK.md`.

Product principle behind all four enhancement phases:

> **Detect, summarize, suggest — never write without a tap.**

Intentions and their progress stay under user control. Listening Sessions
observe and offer. The app never silently changes what the user is tracking or
what their numbers say.

## Review status

Reviewed against the current checkout on August 6, 2026. Enhancement Phases 1
and 2 have no known structural blocker after their stated approval and device
gates. Enhancement Phase 3 has two explicit design blockers that require a
proposal and approval before implementation: AI task routing/cost policy and
ProgressEntry source provenance. Enhancement Phase 4's distinct-session
counting, existing-user migration, and cadence rules must be implemented as
written rather than inferred from occurrenceCount.

---

## Shared ground rules — paste at the top of every phase prompt

```
GROUND RULES FOR THIS TASK

1. Verify before you propose. Read the files named below and confirm the types,
   properties, and function signatures I describe actually exist as stated. If
   anything differs from my description, stop and tell me what you found instead
   of adapting silently. I would rather correct the plan than discover a wrong
   assumption after the code is written.

2. Do not assume you are right. If a requirement is ambiguous, ask before
   building. If you believe part of this plan is a bad idea or carries risk I
   have not accounted for, say so before implementing.

3. Do not modify the existing pipelines. The recording -> transcription ->
   extraction -> progress chain must behave identically after your change.
   Specifically, do not alter: RecorderService, TranscriptionQueue,
   TranscriptionWorker, ExtractionQueue, ExtractorService, ProgressCalculator,
   or any Store's on-disk schema in a backward-incompatible way.

4. Additive changes only. New files preferred over edits to large existing
   files. Where an edit is required, keep it surgical and preserve all existing
   behavior and fallbacks.

5. Flags and Release graduation. New BEHAVIORAL features must sit behind an
   independent DEBUG-on / RELEASE-off flag following the existing pattern in
   Attune/UI/Calendar/CalendarFeature.swift, until physical-device verification
   is complete. Approved copy-only changes do not require a flag and may ship
   directly. After physical verification, report which flags need to be enabled
   for Release and wait for my explicit approval — never enable a Release flag
   silently.

6. New persisted data must be additive and optional. Older JSON must still
   decode. Never break the corrections overlay pattern in ItemCorrection.swift —
   original AI extraction data is always preserved.

7. Tests: add unit tests with fixed sample data for any new pure logic
   (thresholds, parsers, schedulers, matchers). No network in tests.

8. When done, report: files added, files edited, what the feature flag controls,
   how to revert, what you could NOT verify, and any concerns.

9. Do not display confidence or strength scores to the user anywhere. They may
   be used internally to rank or filter only.
```

---

# Enhancement Phase 1 — Naming, copy, and the reminder rewrite

**Risk: very low. No data model changes. Copy and layout only.**

**Prerequisite:** the current `ATTUNE_REMAINING_WORK.md` records physical-device
verification as passed for Voice Check-In and Listening extraction. Confirm that
is still true in the active checkout before starting, but do not repeat a gate
that is already recorded complete.

**No user quotes appear anywhere in Enhancement Phase 1.** A source quote can
expose health, money, relationship, or mental-state content on a lock screen.
Quotes appear only in Enhancement Phase 2, inside the app, where they have
natural context.

```
Read first:
- Attune/App/RootTabView.swift  (tab labels, around line 46)
- Attune/App/DailyReminderNotificationService.swift
- Attune/App/ReminderPreferences.swift
- Attune/UI/Home/HomeView.swift  (header area, around line 130)
- Attune/UI/Home/HomeRecordView.swift
- Onboarding, PaywallView, AboutView, PrivacyDataView, LibraryView,
  SessionListView, SessionDetailView  (all carry "Listening Session" copy)

TASK 1A — Copy inventory FIRST, no edits yet

"Listening Sessions" appears across onboarding, the paywall, privacy copy,
About, Insights, session history, and session detail. Do NOT perform a
mechanical find-and-replace.

Produce an inventory first: every user-facing occurrence, its file and line, and
your proposed replacement. Stop and show it to me before editing anything.
After I approve the inventory, continue the implementation in this same
Enhancement Phase 1 chat; the approval checkpoint does not create another
enhancement phase.

Target vocabulary:
  Feature name .......... Talk it out
  Tab label (visible) ... Talk
  Tab accessibility ..... Talk it out
  Screen heading ........ Talk it out
  Start CTA ............. Start talking
  Active state .......... You're talking it out
  Stop CTA .............. Finish
  History ............... Past sessions
  Internal/technical .... Listening Session (unchanged in code)

Flag anything that reads awkwardly under this vocabulary rather than forcing it.
Take particular care not to rename Voice Check-In recording language, which is a
separate feature and must be untouched.

Do NOT rename: the RootTab.allDay enum case, Session/Segment types, file names,
or any persisted key. Display strings only.

TASK 1B — Neutral daily reminder

DailyReminderNotificationService currently sends:
  "You're only at {percent}% of your intentions today. You can do it!"

Replace with:
  Title: "A quick check-in"
  Body:  "Anything you'd like to log today?"

No percentage, no guilt framing, no user quotes. Same copy for all users.

Preserve exactly: the enabled toggle, the configured hour/minute, today-only
scheduling, the stable request identifier attune.daily.reminder, and the
authorization check.

Perform no network calls and no file I/O inside the notification-center
callback. Determine the body before requesting notification settings. If
avoiding new main-thread disk access would require redesigning an existing
Store, stop and report the conflict rather than implementing it.

This is copy-only, so no feature flag is required.

TASK 1C — Tagline placement

The project currently uses Xcode's generated launch screen, not a customizable
SwiftUI loading view. Do NOT introduce an artificial splash delay to display a
tagline.

Place "Track what matters. Talk out the rest." beneath the Attune wordmark on
the first onboarding screen only. Do not duplicate it in the Talk it out empty
state; that screen gets the concrete occasion copy in Task 1E instead.

If you believe a branded launch experience is worth building, stop and propose
the implementation before writing any of it.

TASK 1D — Center the Home wordmark

The header currently has "Attune" leading and a settings button trailing, so it
is not geometrically centered.

Use a centered overlay, or symmetric 44pt control slots on both sides. The
settings control must remain fully tappable, VoiceOver order must stay sensible,
and nothing may collide at the largest Dynamic Type sizes.

Do NOT apply a metallic or high-gloss gradient. Preserve the current typography
and AttuneTheme colors; this task is alignment and collision-safety only. Show a
simulator screenshot if the environment permits it, and otherwise report that
visual verification remains for the physical-device gate.

TASK 1E — Occasion copy for the Talk it out empty state

Static explanatory copy only — NOT a picker, NOT selectable, and it must not
affect extraction in any way:

  "Think out loud about a decision."
  "Brain dump everything on your mind."
  "Talk through your day."
```

**Verify before Enhancement Phase 2:** reminder fires with the new copy on a physical
device; the tab label renders at the largest Dynamic Type size; the header does
not collide with the settings control; VoiceOver reads the tab as "Talk it out."

---

# Enhancement Phase 2 — Make the end of a session the product

**Risk: low. Read-only over existing stored data.**

Right now a finished session produces a list. Lists are not memorable. One
sentence is. This screen is the feature's demo and the thing users repeat to
other people.

```
Read first:
- Attune/Models/ExtractedItem.swift
- Attune/Models/TopicAggregate.swift
- Attune/Storage/TopicAggregateStore.swift  (loadTopics, update(with:))
- Attune/Storage/ExtractionStore.swift
- Attune/Storage/CorrectionsStore.swift
- Attune/Storage/ItemResolver.swift
- Attune/Storage/SessionStore.swift
- Attune/Models/ItemCorrection.swift
- Attune/UI/Home/HomeRecordView.swift
- Attune/UI/Library/SessionDetailView.swift
- Attune/UI/Library/InsightsListView.swift and InsightDetailView.swift
- Attune/Understanding/ExtractionQueue.swift  (to find where extraction
  completes — do not change its behavior)

TASK — Session Recap screen

When extraction for a session finishes, show a recap. Structure:

1. ONE headline sentence at the top. Pick the single most interesting true
   observation available, in this priority order:
     a. A recurring topic: "You mentioned {topic} across {n} sessions this
        month." Do NOT use TopicAggregate.occurrenceCount as a session count;
        it is a lifetime mention count. Resolve the topic's itemIds, apply the
        corrections overlay, resolve their parent Sessions, filter by each
        Session.startedAt in the user's current calendar month, and count
        distinct sessionIds. Do not use extractedAt as the session date. The
        topic must occur in the current session and at least one earlier session
        in that month. If that cannot be derived reliably, skip this branch.
     b. Commitment count: "Two things you said you'd do." (Correct
        pluralization.) Count the effective corrected type, not only the
        original AI type.
     c. Neutral fallback: "{n} things worth remembering." For zero eligible
        captures, use "Nothing new was captured." rather than "0 things."
   The headline must be literally true and derivable from stored data. If you
   cannot produce a true interesting sentence, use the neutral fallback. Never
   speculate, never infer emotion, never diagnose.

2. Below it, the captures as they appear today, unchanged.

3. Quotes belong here, not in notifications. Show at most ONE quote in the
   recap, selected from eligible captures in this session:
       You said: "{sourceQuote}"

   Quote selection must be a pure, deterministic function:
     - Select the newest eligible item by extractedAt.
     - Eligible = the effective corrected type is "intention" or "commitment",
       sourceQuote is nonempty after trimming, and the corrections overlay does
       not mark the item incorrect. Do not invent a separate hidden/rejected
       correction state that the current model does not have.
     - Normalize repeated whitespace.
     - Truncate the QUOTE (not the surrounding text) to at most 100
       user-perceived characters at the last word boundary, appending a single
       Unicode ellipsis only when truncation actually occurred.
   Unit-test eligibility, ordering, normalization, and truncation boundaries.

Rules:
- Read-only. Do not write anything new to disk in this phase.
- Do not change ExtractionQueue, ExtractorService, or the transcription chain.
  Observe completion; do not restructure it.
- Recap must render correctly for: zero captures, one capture, and a session
  where every capture was marked incorrect via the corrections overlay.
- Respect corrections: items marked incorrect are excluded from counts,
  headline selection, recurring-topic evidence, and quote selection.
- Recap must be reachable again later from the session detail view, not only
  once immediately after processing.
- Unit-test headline selection with fixed fixtures covering every branch above.

Flag: SessionRecapFeature.isEnabled
```

**Verify before Enhancement Phase 3:** run real sessions on a physical device covering a
first-ever session, a session repeating an earlier topic, and a session where
you mark all captures incorrect.

---

# Enhancement Phase 3 — Progress candidates from a Listening Session

**Risk: medium-high. Touches AI policy and progress provenance. Confirmation is
required at both design checkpoints before implementation.**

If someone says "I did three more pages" during a Talk it out, that should be
capturable — but the write must always be a deliberate tap. Silent progress
changes would make Momentum move for reasons the user cannot see.

```
Read first:
- Attune/AI/CheckInExtractorService.swift  (reference its input/output semantics;
  it is a network-backed AI extractor, not a reusable pure matcher)
- Attune/AI/OpenAIClient.swift and backend/openai-proxy/V2_API.md
- Attune/Models/CheckInUpdate.swift
- Attune/Models/Intention.swift
- Attune/Storage/IntentionStore.swift, IntentionSetStore.swift
- Attune/Storage/ProgressStore.swift
- Attune/Understanding/ProgressCalculator.swift
- Attune/Storage/ItemResolver.swift
- The Enhancement Phase 2 Session Recap you just built

TASK — Detect progress mentions, surface them, write only on confirmation

1. After a Listening Session's extraction completes, evaluate the session
   transcript for statements that map to the user's CURRENT ACTIVE intentions,
   preserving CheckInExtractorService's update semantics for Intention.aliases,
   INCREMENT versus TOTAL, amount, unit, evidence, and optional occurrence time.

2. Surface any matches on the Session Recap as unconfirmed suggestions:
     "Sounds like you did 3 more pages — log it?"   [Log]  [Dismiss]

3. Write to ProgressStore ONLY when the user taps Log. Dismiss discards it
   permanently and must not re-offer that same statement.

4. A confirmed write must be indistinguishable in the data from a normal
   progress entry, so Momentum, DayDetailView, and overrides all continue to
   work with no special-casing. Confirm this by reading ProgressStore and
   ProgressCalculator before writing code, and tell me if it is not true.

KNOWN EXTRACTION/POLICY CONFLICT — resolve before implementation:
- CheckInExtractorService does not contain a local matcher to reuse. It performs
  a network-backed AI extraction using Check-In-specific routing and policy.
- Calling it again for every Talk it out session would add an AI request, cost,
  failure mode, and server-policy decision. Reusing a fake CheckIn ID or silently
  sending Talk it out traffic through the Check-In route is not acceptable.

First report whether progress candidates can be derived defensibly from the
already-produced session transcript/extractions without a new AI request. If
not, propose the server-owned task/route, payload, usage controls, retry and
billing-error behavior, and Release fallback. Do not add or repurpose a network
route until I approve that proposal. Unit tests may cover deterministic parsing,
validation, ranking, and persistence of fixed candidate fixtures; do not claim
they validate semantic AI matching.

KNOWN CURRENT-MODEL CONFLICT — resolve before implementation:
- ProgressEntry currently requires sourceCheckInId.
- MomentumPointAdapter has paths that only include entries whose
  sourceCheckInId matches a real CheckIn.
- Therefore a Talk it out session entry is NOT currently guaranteed to be
  indistinguishable from a normal Check-In entry.

Do not create a synthetic/phantom CheckIn and do not put a Session ID into a
field while pretending it is a CheckIn ID. First propose the smallest additive,
backward-compatible provenance change and the exact consumers that would need
updates. Older ProgressEntry JSON must still decode and existing Check-In
entries must behave identically. Stop for my approval before implementing that
provenance change.

Hard constraints:
- NEVER write progress without an explicit user tap. This is the core rule.
- Do not modify the Voice Check-In flow, CheckInStore, or check-in behavior in
  any way. This is a separate, parallel path. A narrowly scoped update to a
  shared read adapter is allowed only after the provenance proposal above is
  approved and only if existing Check-In output remains identical.
- Do not create, rename, or deactivate intentions in this phase. Matching
  against existing active intentions only. If nothing matches, show nothing.
- Show at most 3 progress suggestions per session, ranked by match quality.
- Persist dismissal and accepted outcomes in a new additive store keyed by a
  stable candidate identity; do not mutate Session, CheckIn, or ProgressEntry
  merely to remember an outcome. Unit-test candidate validation/ranking,
  candidate identity, and permanent accepted/dismissed behavior with fixed
  fixtures.

Flag: SessionProgressCaptureFeature.isEnabled

Before implementing, report: your candidate-extraction approach and its network
implications, how you rank suggestions, where outcomes are persisted, the
provenance migration proposal, and any risk that a confirmed write could
double-count against an existing check-in entry for the same activity.
```

**Verify before Enhancement Phase 4:** on a physical device, state progress during a
session, confirm one and dismiss one, then check Momentum and Day Detail. Also
confirm a check-in and a session mention of the same activity do not
double-count in a way that surprises you.

---

# Enhancement Phase 4 — Suggested intentions from recurring topics

**Risk: medium. New engine, but fully additive and user-accepted.**

This is the payoff. The app observes what someone keeps talking about and offers
an intention. The user accepts or declines — so intentions stay theirs.

**Approved implementation revision:** Do not merely turn the topic title into an
intention and do not choose from predefined actions. Once the local engine
qualifies a recurring topic, the server-owned AI route may compose one fully
custom, measurable micro-intention—or return no suggestion. It receives the
corrected evidence, active intention configuration, recent progress-day counts,
and prior suggestion outcomes. The Worker validates the generated behavior,
evidence IDs, supported units, safety, active-intention duplication, and
declined/recent repetition before returning it. Model-invented citations are not
accepted. This is one extra AI call only after a topic qualifies.

**Approved cadence revision:** Reevaluate immediately whenever a Talk it out
session finishes processing. Every user gets an introduction period for this
new feature: days 0-20 use a two-distinct-session floor and three-day cooldown.
After day 20, require three distinct sessions spanning at least three days and
use a four-day cooldown. Completion observation must not modify
`ExtractionQueue`.

**Approved focus-mode revision:** After the previous two full local-calendar
days contain no progress entry or manual override, Home may enter a reversible
One Thing Mode. It focuses the first intention and visually mutes the others,
but never changes or deletes the IntentionSet. The user can switch or exit.
When a suggestion arrives at the tier limit, stage an explicit replacement of
the first zero-progress intention, otherwise the lowest three-day average, in
the normal editor; persist only on Save.

## On the onboarding cadence

Your instinct is right: a pure "4+ mentions across 2+ weeks" gate means a new
user never sees this feature and never learns it exists. The graduated schedule
solves the cold start. Adjustments I'd make:

- **Keep a floor of 2 distinct sessions even during onboarding.** Suggesting
  from a single session is a coin flip, and a bad first suggestion permanently
  teaches the user to ignore this feature. Lower the bar, don't remove it.
- **Silence beats a weak suggestion.** If nothing qualifies, show the "record
  more" nudge or nothing at all.
- **One outstanding suggestion at a time, plus a global cooldown**, so the
  onboarding schedule and the steady-state rule can never stack or double-fire.
- **Trim the hedged copy.** One clause of humility, not two — over-apologizing
  reads as the app not trusting itself.

```
Read first:
- Attune/Models/TopicAggregate.swift
- Attune/Storage/TopicAggregateStore.swift
- Attune/Storage/ItemResolver.swift, CorrectionsStore.swift, SessionStore.swift
- Attune/Understanding/Canonicalizer.swift, TopicKeyBuilder.swift
- Attune/Models/Intention.swift, IntentionSet.swift
- Attune/Storage/IntentionStore.swift, IntentionSetStore.swift
- Attune/UI/Home/AddEditIntentionView.swift, EditIntentionsView.swift
- Attune/App/SubscriptionAccessPolicy.swift, SubscriptionConfig.swift
- Attune/UI/Home/HomeView.swift

TASK 4A — Suggestion engine (pure logic, own file, fully unit-tested)

Build a pure, testable engine that decides whether to offer a suggested
intention right now. No UI and no persistence in this type — it takes state in
and returns a decision out.

Signals available: TopicAggregate.itemIds, topicKey, displayTitle, categories;
resolved corrected items and their parent Session.startedAt values; days since
first launch; current active intentions; suppression list; suggestion history.
Do not use raw occurrenceCount as a distinct-session signal.

Cadence:

  INTRODUCTION (days 0-20 after this feature's first-launch date):
    - Minimum 2 distinct qualifying sessions.
    - At most one suggestion every 3 days.

  ESTABLISHED (day 21 onward):
    - Minimum 3 distinct qualifying sessions spanning at least 3 days.
    - At most one suggestion every 4 days.

Universal rules that override everything above:
  - Never more than ONE outstanding, unanswered suggestion at a time.
  - The applicable 3-day or 4-day cooldown is global across topics. The
    schedules must not be able to stack.
    A "record more" nudge is not an intention suggestion and does not consume
    the suggestion cooldown, but show it at most once per evaluation day.
  - A declined behavior fingerprint and close title rewrites are suppressed
    permanently. Do not ban its entire broad topic; a meaningfully different
    action may be considered after the normal cooldown.
  - Hold an accepted fingerprint out for 60 days to preserve variety. An
    inactive accepted intention may be considered again after that period.
  - Never suggest an action that duplicates an existing active intention (check
    title and aliases).
  - A user at their active-intention limit may still receive one suggestion;
    stage an explicit editor-reviewed swap and persist only on Save.
  - If no topic qualifies, return no suggestion. Silence is the default.

Counting rule:
  - TopicAggregate.occurrenceCount is a lifetime ITEM-MENTION count, not a
    distinct-session count. Resolve itemIds, apply corrections, resolve each
    parent Session, and count unique sessionIds for every threshold and every
    user-facing evidence statement.
  - For "this month," filter using parent Session.startedAt in the user's
    current calendar month before counting unique sessionIds. Do not use an
    item's extraction timestamp as the session date.
  - If itemIds cannot be resolved reliably, the topic does not qualify.

Existing-user migration rule:
  - Record first-launch date for genuinely new installs.
  - If this new store is absent but the user has completed onboarding or has
    persisted Attune data, treat them as an existing user and enter STEADY STATE.
    Do not initialize them as Day 0 and replay new-user onboarding suggestions.

Unit-test every branch and every boundary with injected dates and fixtures. No
real clock reads inside the engine — pass the date in.

TASK 4B — Suggestion card UI

Where: Home, below existing content. One card, dismissible, never a feed.

Content:
  - One complete small action composed for the user's qualified evidence and
    validated by the Worker. No fixed action catalog.
  - Evidence, always: "You've brought up {topic} in {n} sessions this month."
    Here `{n}` must use the corrected, current-month distinct-session count
    defined above, never TopicAggregate.occurrenceCount.
  - Tap-through to the underlying captures and quotes via itemIds.
  - Actions: [Add this]  [Not for me]

Onboarding copy carries exactly one clause of hedging, for example:
  "Still early, but based on your first few sessions — maybe {topic}?"

"Add this" opens the existing intention editor prefilled with the validated
title, target, unit, and timeframe. All fields stay editable and visible. The
action remains only a suggestion until the user explicitly taps the editor's
normal Save button.

"Not for me" permanently suppresses that behavior fingerprint and close
rewrites. Other genuinely different actions for the topic may be considered
after the normal cooldown.

Nothing is created until the user completes the existing intention editor and
saves through the normal path.

TASK 4C — Persistence

New additive store for: suggestion history (actionId, topicKey, optional title,
behavior fingerprint and family, date, outcome),
outstanding suggestion, completed onboarding opportunities, cooldown state,
and first-launch date. Must decode safely when absent for existing users. Do
not touch existing store schemas.

DO NOT BUILD IN THIS PHASE:
- Any mood, stress, or emotional-tone correlation. Frequency only. Suggesting
  from a countable, showable number is defensible; suggesting from inferred
  stress is the app diagnosing the user, and it will be wrong in ways that feel
  invasive. Do not use tone even as a hidden tiebreaker; break frequency ties
  deterministically using recency and then a stable topic key.
- Auto-creation of intentions under any circumstance.
- Any change to the check-in, progress, or Momentum pipelines.

Flag: IntentionSuggestionFeature.isEnabled

Before implementing, report your read of the cadence rules, how distinct
sessions are derived, how existing installs bypass new-user onboarding cadence,
and any case where two rules could fire on the same day.
```

**Verify:** unit tests for every cadence branch, custom response validation,
fragmented-topic consolidation, legacy JSON decoding, active duplicates,
permanent declined behavior suppression, 60-day accepted novelty, sensitive
evidence, and orphan evidence. Then verify on a physical device with two related
sessions during days 0-20, three related sessions spanning three days after day
20, a decline followed by a meaningfully different idea on the same topic, and
a user already at their intention limit.

---

# Deferred — decide separately

**Free tier rebalance.** Currently free users get one intention, one check-in
per day, no Insights, and today's Momentum only — so they never see the Talk it
out output that makes Attune distinctive, which makes conversion hard. Worth
considering: one full lifetime Talk it out session with complete Insights
output, then locked. "You've used your free session" converts better than "this
feature is Pro." This is a pricing decision, not an engineering one, so it needs
your call before it becomes a prompt. It also touches SubscriptionAccessPolicy,
so it should not be bundled with any phase above.

**Ask your life / semantic search over transcripts.** High cost, demo-friendly,
low sustained use. Revisit only if users ask for it.

**Pattern detection across mood and topics.** Highest risk-to-reward ratio in
the backlog. Leave alone until the safe frequency-based version has been in
users' hands.

**Optional Home quote card.** Showing "You said: '…'" on Home raises its own
questions — when it appears, how often, how it's dismissed, whether quotes go
stale, and whether opening a notification should trigger it. That is a
behavioral feature, not copy. Test it separately after Enhancement Phase 2 ships, only if it
still seems valuable once quotes exist in the recap.

**Opt-in quoted notifications.** If quotes in the recap prove valuable, a
"Use my words in reminders" setting defaulting to OFF could follow, with a plain
explanation that quotes may appear in lock-screen previews. Not before.
