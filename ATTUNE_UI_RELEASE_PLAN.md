# Attune UI and App Store Release Plan

Last updated: 2026-08-05

This is the durable restart document for the Attune UI work. In a new Codex chat, ask the agent to read this file, inspect `git status` and the latest entries in **Change log**, then continue the first incomplete phase. Do not rely on chat history.

## Product direction

- Preserve Attune's dark teal identity, but make it calmer, clearer, and more consistent.
- Use four primary destinations: **Today**, **Record**, **Insights**, and **Momentum**.
- Open Settings from the gear button on Today instead of a fifth tab.
- Keep recording, transcription, storage, subscription, and progress behavior unchanged during UI phases unless a phase explicitly says otherwise.
- Keep developer diagnostics in Debug builds and remove raw implementation language from the consumer experience.
- Verify every phase with an Xcode build, simulator walkthrough, and screenshots before continuing.

## Product behavior contract

- **Voice Check-In** updates the user's existing tracked intentions and optional mood. It requires an explicit amount; “more” creates an increment and “total today” sets the running total.
- **Listening Session** is a separate background recording. It extracts and categorizes intentions, commitments, events, and states; repeated topics increase recurring-theme counts shown through Insights.
- Listening Sessions do **not** silently create quantitative tracked intentions or alter Today's progress. A future consumer flow should let the user confirm and promote a captured intention into tracking.

## Consumer feedback policy

- Main screens show only current state, useful results, and problems the user can act on.
- Keep microphone/permission problems visible because they include an **Open Settings** action; keep a recording-start failure inline because the user can retry.
- Do not leave transcription, segment, extraction, interruption, or saved-session warnings on Today or Record when the user cannot repair them there. Preserve those details in Sessions and Debug diagnostics.
- Insights must describe only stored extracted items and recurring topic aggregates. Do not imply that an insight changed tracked progress or created an intention unless the user explicitly confirms that action.

## Baseline and safety

- Branch at start: `wip/pre-appstore-changes`
- Baseline commit: `1573e22b0939500cdea1d399316c6c64a30d76f5`
- Existing uncommitted work predating the UI phases:
  - `Attune/Attune.xcodeproj/project.pbxproj`
  - `Attune/Attune.xcodeproj/xcshareddata/xcschemes/Attune.xcscheme`
  - `Attune/Attune/App/SubscriptionManager.swift`
  - `Attune/Attune/Attune.entitlements`
- Those changes configure StoreKit/platform support and Debug premium access. Preserve them.
- `Attune/Attune/AI/Secrets.swift` is local and gitignored. Never print, commit, or expose its values.
- Do not commit, push, publish GitHub Pages, or submit to Apple without Scott's approval.

## Phase checklist

### Phase 0 — Baseline and durable plan (implementation complete)

- [x] Inspect repository lineage, branch, status, and existing diffs.
- [x] Confirm the current app builds before UI edits.
- [x] Capture the current Home, All Day, Library, Momentum, Settings, About, paywall, mood, and intention flows.
- [x] Create this restart document.
- [ ] Create an approved checkpoint commit after Phase 1 review.

### Phase 1 — Design foundation, navigation, and required public pages (implementation complete; publishing pending)

- [x] Add shared semantic Attune design tokens and reusable component styles.
- [x] Reduce excessive background/glass glow without changing screen layouts.
- [x] Use a consistent dark appearance across sheets, lists, and tabs.
- [x] Simplify root navigation to Today, Record, Insights, and Momentum.
- [x] Move Settings to a gear button on Today.
- [x] Add GitHub Pages-ready privacy, support, and terms pages under `/docs`.
- [x] Replace placeholder legal links with the expected GitHub Pages URLs.
- [ ] Add a private support/privacy email before App Store submission.
- [ ] Publish GitHub Pages from the default branch `/docs` folder and verify every URL.
- [ ] Enter the published privacy URL and App Privacy answers in App Store Connect.

Acceptance: app builds; all four tabs work; Settings opens and closes; Home-to-Momentum routing works; public-page links are correct once Pages is published.

### Phase 2 — Today, check-ins, intentions, and mood (implementation complete; on-device success verification pending)

- [x] Reorder Today so Record Check-In is the hero action.
- [x] Implement polished idle, recording, processing, success, failure, and permission-denied states.
- [x] Improve contrast and tab-bar safe-area spacing.
- [x] Redesign Add/Edit Intentions without changing stores or parsing.
- [x] Clarify daily/weekly targets, unit selection, validation, and deletion.
- [x] Redesign Mood around one understandable score plus optional tags.
- [x] Replace consumer-facing `GPT` language with `Attune` language.
- [x] Allow first-time Speech Recognition and live-test recording → processing → recoverable failure.
- [ ] Verify successful transcription and saved-state UI on a physical device; the iOS Simulator recognizer failed to initialize.

### Phase 3 — Record / Listening Sessions (implementation complete; physical-device transcription/interruption verification pending)

- [x] Apply the shared Attune visual system.
- [x] Explain Check-In versus Listening Session.
- [x] Replace the unlabeled record control with an accessible primary action.
- [x] Hide segment and queue implementation details.
- [x] Add polished idle, recording, processing, interruption, failure, and permission states.
- [x] Improve history and subscription entry points.
- [ ] Verify successful transcription and a real interruption recovery on a physical device.

### Phase 4 — Insights and history (implementation complete)

- [x] Replace the Library debug cockpit with consumer-first Recent, Check-Ins, Sessions, Topics, and Insights views.
- [x] Remove Segments from production navigation.
- [x] Replace IDs with readable session titles and dates.
- [x] Hide fingerprints, file metadata, and confidence values behind Debug diagnostics.
- [x] Simplify insight review/correction language.
- [x] Follow the consumer feedback policy: no persistent non-actionable processing warnings or raw failure banners.
- [x] Clearly distinguish captured items from recurring themes and from quantitative tracked intentions.
- [x] Add useful search, filters, and empty states.

### Phase 5 — Momentum and progress (complete; populated-data validation passed)

- [x] Refine Day/Week/Month navigation and empty states.
- [x] Consolidate duplicate Library Progress views into Momentum drill-down.
- [x] Improve chart contrast, accessibility, selection, and labels.
- [x] Add compact summaries and consistent intention color/symbol identity.
- [x] Validate Day, Week, and Month with removable simulator-only historical data built from Scott's existing intentions.

### Phase 6 — Settings, onboarding, privacy, and paywall (UI implementation complete; production AI rollout pending)

- [x] Reorganize Settings into Membership, Notifications, Privacy & Data, and Support; do not invent an account system the app does not have.
- [x] Add readable microphone, speech-recognition, and notification permission status plus an iOS Settings entry point.
- [x] Replace export `training purposes` language with backup and personal-record language.
- [x] Add short benefit-led onboarding followed by the existing AI/privacy disclosure.
- [x] Brand and validate the Attune Pro paywall and StoreKit loading/unavailable/error states.
- [x] Polish About, support, legal, and data-request entry points.
- [ ] Finalize provider-specific AI disclosure after the approved Cloudflare/OpenAI gateway rollout is complete.

### Production AI gateway — staged separately from UI phases

- [x] Approve Cloudflare as the server-owned OpenAI gateway and reuse its existing OpenAI secret.
- [x] Implement backward-compatible request validation, safe limits, timeout handling, an emergency switch, metadata-only logging, and local contract tests.
- [x] Deploy after Scott approves the reviewed Worker diff; live `/v1` verification passed.
- [x] Implement, deploy, and live-smoke-test server-owned task endpoints for Check-In, voice intentions, and Listening Session extraction.
- [x] Add a per-feature Debug-only iOS `/v2` switch and enable voice intention parsing first; Debug and Release builds pass and Release remains on `/v1`.
- [x] Physically verify Debug voice intention parsing through `/v2`.
- [ ] Migrate and physically verify Check-In through `/v2`, followed by Listening Sessions.
- [ ] Add App Attest, StoreKit verification, D1 usage/entitlement accounting, and per-install limits.
- [ ] Migrate the app through TestFlight and retire the shared proxy-token endpoint after physical-device validation.

### Phase 7 — Accessibility, release QA, and marketing capture

- [ ] VoiceOver labels/hints and non-color status communication.
- [ ] Dynamic Type, contrast, Reduce Motion, and touch-target audit.
- [x] Small/large iPhone and iPad simulator checks.
- [ ] Offline, denied-permission, StoreKit, and processing recovery checks.
- [ ] Debug and Release builds.
- [ ] App Store metadata/privacy/link review.
- [ ] Populate marketing data and record final 9:16 app footage.

## Public-page deployment

The repository remote is `https://github.com/scootero/Attune.git`. The prepared Pages URLs are:

- `https://scootero.github.io/Attune/`
- `https://scootero.github.io/Attune/privacy/`
- `https://scootero.github.io/Attune/support/`
- `https://scootero.github.io/Attune/terms/`

After the approved changes reach the default branch, open GitHub repository **Settings → Pages**, choose **Deploy from a branch**, select the default branch and `/docs`, then save. Verify all four URLs before App Store submission.

## Change log

### 2026-08-04 — Phase 0 and 1

- Added this durable implementation plan.
- Added the shared Attune theme foundation and reduced Home glass/background intensity.
- Simplified root navigation to four tabs and moved Settings to Today.
- Added a visible Done control so sheet-based Settings can always be closed.
- Added GitHub Pages-ready privacy, terms, and support pages.
- Wired in-app legal links to the expected Pages URLs.
- Verification results are recorded below after the final Phase 1 build and walkthrough.

### 2026-08-04 — Phase 2

- Moved Daily Check-In to the top of Today and rebuilt it as the primary hero.
- Added requesting-permission, denied-permission, recording, processing, success, and recoverable failure presentations.
- Added explicit microphone/speech authorization handling without changing transcription or extraction stores.
- Reworked Mood into one 0–10 score with optional feeling tags and Attune-first language.
- Clarified intention targets, units, daily/weekly periods, validation, and deletion while preserving persistence and parsing.
- Increased Today bottom spacing so content clears the tab bar.

### 2026-08-04 — Phase 3

- Rebuilt Record as a consumer-facing All Day screen using the shared Attune cards, colors, spacing, and button styles.
- Added a labeled and accessible Start All Day Session action plus clear recording, processing, permission, interruption, and failure states.
- Explained Check-In versus All Day without exposing segment numbers, queue counts, or internal recorder mechanics.
- Added synchronized Today counts and direct Sessions/Insights entry points.
- Kept RecorderService, session persistence, audio segmentation, transcription, and extraction behavior unchanged.
- Corrected the subscription presentation to reflect effective feature access in Debug while retaining entitlement gating in Release.

### 2026-08-04 — Product-contract and noise correction

- Traced both recording pipelines and documented the actual behavior contract above.
- Simplified Today to four visible elements: Voice Check-In, Weekly Momentum, Today's Progress, and Mood; removed the duplicate summary strip and surfaced the chart above the fold.
- Made Check-In instructions explicit, report only persisted progress/mood changes, require numeric fallback amounts, and preserve “more” versus “total today” semantics.
- Renamed consumer-facing All Day language to Listening Session without changing the recorder, background audio, transcription, extraction, or topic aggregation pipeline.
- Simplified Record to one session card and compact Sessions/Insights history; processing waits for extraction and history shows the real captured-item count.
- Removed persistent Record completion/transcription banners. Non-actionable failures remain available in Sessions; only permission and start failures stay on the main screen because the user can fix or retry them.

### 2026-08-04 — Phase 4

- Replaced the Library/Segments debug cockpit with a consumer Insights home containing recurring themes, recent captures, and listening/check-in history.
- Built Captured and Themes views directly from stored `ExtractedItem` and `TopicAggregate` data, with search and capture-type filters.
- Derived visible theme counts from resolved items after corrections so hidden captures do not inflate recurring counts.
- Replaced fingerprints, confidence/strength percentages, session IDs, segment indexes, raw statuses, and technical failures with titles, summaries, quotes, dates, types, categories, and mention counts.
- Added a Review Capture sheet that can correct title/type/categories, add a personal note, or hide a capture from consumer summaries.
- Clarified that captures and themes do not update Today or create tracked intentions.
- Simplified Listening Session history/details to dates, duration, captures, and available transcript; failed transcription produces no persistent warning.

### 2026-08-04 — Phase 5

- Replaced the noisy explanatory card and custom 3D charts with a compact Day/Week/Month hierarchy and readable Swift Charts.
- Kept Momentum grounded in stored tracked intentions, check-in progress entries, manual overrides, and mood; no listening-session capture changes Today progress.
- Stopped rendering empty historical days as red/zero progress bars. Week and month charts now show only days with recorded progress.
- Added period-aware summaries, goal selection on the Day chart, percent labels, target reference, VoiceOver descriptions, and stable color plus symbol identities.
- Moved the former standalone Progress UI into a toolbar-accessible Progress History drill-down, preserving daily details, audit entries, and manual total adjustments.
- Corrected the paywall loading indicator to explicitly use SwiftUI's spinner after removing the conflicting standalone `ProgressView` type.

### 2026-08-05 — Home hierarchy correction

- Reordered Today around the product workflow: Intentions and today's progress, Voice Check-In, Mood, then Weekly Momentum.
- Renamed the first card to Intentions with a Today's progress subtitle and added target/unit/timeframe context to every row.
- Kept Add Intention visible whenever the card is in its normal state; it opens the existing add/edit intention flow without changing persistence.
- Renamed the manual override action to Update Progress while preserving the existing slider, Save, Cancel, and override behavior.
- Compacted the Voice Check-In instructions and example without changing recording, transcription, parsing, ambiguity, progress, or mood behavior.
- Replaced the oversized check-in failure presentation with a compact inline state that auto-dismisses after eight seconds; saved receipts return to idle after five seconds.
- Rendered days with no recorded progress as neutral empty marks on Home instead of red failure bars; actual recorded ratios and streak logic are unchanged.
- For populated Momentum visual QA, use removable simulator fixtures or an explicitly DEBUG-only demo-data tool; do not ship fabricated history.

### 2026-08-05 — Simulator-only Momentum demo data

- Added a DEBUG + Simulator-only Settings tool that creates approximately fourteen days of ordinary `CheckIn` and linked `ProgressEntry` JSON records using the four existing intentions; it never duplicates or edits those intention files.
- Namespaced every generated record with `ATTUNE_DEMO_` and recorded every exact created path plus protected intention-file hashes in `Documents/Attune/MomentumDemoManifest.json`.
- Added **Remove and Verify Demo Data**, which deletes manifest paths, performs a second type-aware reserved-ID scan for interrupted/orphaned runs, verifies zero residue, and reports whether protected intentions changed.
- Kept a non-Debug launch purge in `AttuneApp` so installing Release over a Debug simulator container cannot carry demo history forward. The seeder and Settings controls do not compile into Release or onto a physical device.
- The authoritative cleanup contract and future-removal handoff comments are at the top of `Storage/MomentumDemoDataManager.swift` and beside the Settings controls. Do not remove only the UI; first run cleanup and retain the non-Debug residue purge.
- Current simulator handoff state: the Debug build is installed and one 17-check-in/68-progress-entry demo run is intentionally loaded for review. Remove it from **Settings → Developer → Remove and Verify Demo Data**.

### 2026-08-05 — Phase 6

- Reorganized Settings around Membership, Notifications, Privacy & Data, and Support while preserving Debug-only diagnostics and Momentum cleanup controls.
- Replaced Attune Monthly marketing with Attune Pro and removed consumer-facing “background listening” sales language.
- Built a branded paywall and then aligned the real feature gates to the approved plan: Free has one active intention, one Voice Check-In per day, today's Momentum only, and the daily reminder; Pro adds more intentions, unlimited check-ins, Listening Sessions, Insights, historical/Week/Month Momentum, voice intention setup, and data export.
- Explained that Listening Sessions organize clear intentions, commitments, events, and states and group repeated ideas into themes; event-like captures do not currently create calendar appointments or event reminders.
- Added first-run benefit onboarding before the existing mandatory processing disclosure.
- Added microphone, speech, and notification status plus accurate recording, online-processing, local-storage, export, and data-request information.
- Set the new-install reminder preference to on at 6 PM; iOS notification authorization is still required before delivery.
- Updated the local StoreKit product to $4.99/month with a three-day free-trial offer and made trial messaging eligibility-aware. The matching offer must still be configured and verified in App Store Connect.
- Improved StoreKit loading, unavailable, purchase, restore, and trial states without changing the product ID or Release entitlement verification.
- Superseded August 6, 2026: version 1.0 now intentionally has no introductory
  trial; the local offer and all trial advertising were removed in Phase 1.
- Left the existing Cloudflare/OpenAI request architecture and provider-specific disclosure unchanged pending Scott's requested production-API discussion.

### 2026-08-05 — Production AI gateway rollout checkpoint

- Deployed and live-verified the hardened backward-compatible `/v1/chat/completions` route.
- Added, deployed, and live-smoke-tested server-owned `/v2` routes for voice
  intentions, Voice Check-In, and Listening Session extraction. Each returned
  HTTP 200, contract version 1, the expected response shape, and a request ID;
  an unauthenticated probe correctly returned 401.
- Added a shared iOS `/v2` task client with independent Debug-only feature
  switches. Enabled voice intention parsing first; Check-In and Listening
  Sessions remain on `/v1`, and all Release routing remains on `/v1`.
- Preserved the existing parser, progress persistence, extraction queue, local
  storage, UI, and Debug premium bypass. No Momentum files were changed for
  this rollout.
- Detailed request contracts and migration status are in
  `backend/openai-proxy/V2_API.md`.

## Verification log

- Pre-change build: succeeded for iPhone 17 Pro simulator on iOS 26.5.
- Phase 1 build: succeeded for iPhone 17 Pro simulator on iOS 26.5.
- Phase 1 simulator walkthrough: passed Today, Record, Insights, Momentum, Today-to-Momentum routing, and Settings open/close.
- Public pages: local HTTP checks returned 200 for home, privacy, support, terms, and stylesheet.
- Remaining external verification: add the private support email, publish GitHub Pages, then verify the public URLs and App Store Connect entries.
- Phase 2 build: succeeded for iPhone 17 Pro simulator on iOS 26.5; no new compiler warnings.
- Phase 2 visual walkthrough: passed Today hierarchy, Mood selection/cancel, Intentions expand/edit/cancel, and denied-microphone recovery.
- Phase 2 recording walkthrough: Scott allowed Speech Recognition; recording start/stop, processing, and recoverable failure UI passed.
- Simulator limitation: Apple Speech failed with `Failed to initialize recognizer`, so successful transcription/saved-state UI remains an on-device verification item.
- Phase 3 pre-edit behavior check: the original All Day UI started a real session, advanced its timer, created audio, stopped into processing, queued transcription, and finalized the saved session; the Simulator recognizer failed as above.
- Phase 3 build: succeeded for iPhone 17 Pro simulator on iOS 26.5; `git diff --check` passed.
- Phase 3 final walkthrough: passed idle hierarchy, accessible Start/End actions, Check-In versus All Day explanation, synchronized Today count, Sessions sheet, Insights empty state, and effective subscription presentation.
- Phase 3 recording walkthrough: created and saved a real session, kept recording after leaving the Record tab, and advanced from `00:02` to `01:30` across an actual simulator lock/unlock.
- Phase 3 processing result: the UI truthfully showed the real recognizer failure; logs and saved JSON confirmed audio creation, processing/queue transitions, a complete session record, and one failed transcription segment.
- Phase 3 source verification: background audio mode, three-minute segmentation, interruption persistence, and queue finalization remain implemented in the existing recorder services. A physical-device interruption/transcription success test is still required.
- Product-contract correction build: succeeded for iPhone 17 Pro simulator on iOS 26.5; `git diff --check` passed.
- Product-contract visual walkthrough: Weekly Momentum and the complete Today hierarchy are visible above the tab bar; Record contains one Listening Session card plus compact history.
- Listening control walkthrough: Start entered the real background recording state and End entered real processing. The Simulator again produced its known speech-recognizer failure; that diagnostic remains available inside Sessions.
- Non-actionable-banner correction: build succeeded and the simulator confirmed Record stays clean even with four saved sessions containing failed transcription; no stale “Session needs attention” notice remains.
- Phase 4 build: succeeded for iPhone 17 Pro simulator on iOS 26.5; `git diff --check` passed.
- Phase 4 empty-state walkthrough: passed Insights onboarding copy, clean four-session history, readable session detail, and back navigation with no technical failure banners.
- Phase 4 populated walkthrough: passed summary counts, recurring-first themes, recent captures, Captured/Themes navigation, search/filter controls, capture detail, Review Capture, and two-mention theme detail using temporary simulator fixtures; fixtures were removed afterward.
- Phase 5 build: succeeded for iPhone 17 Pro simulator on iOS 26.5; `git diff --check` passed.
- Phase 5 Day empty-state walkthrough: passed compact hierarchy, period navigation, factual zero summary, no fake chart bars, actionable check-in guidance, daily-details link, and Progress History accessibility entry.
- Earlier Phase 5 pause: Week, Month, and Progress History inspection had paused when the Mac locked; the removable demo-data walkthrough below resolved the populated-chart requirement.
- Home hierarchy correction build: succeeded for iPhone 17 Pro simulator on iOS 26.5; `git diff --check` passed.
- Home populated walkthrough: passed four persisted intentions with target labels, always-visible Add Intention, existing intention-manager presentation, Update Progress slider presentation/cancel, compact Voice Check-In, Mood, and Weekly Momentum ordering.
- Home failure walkthrough: a real Simulator recognizer failure rendered the compact inline message and automatically returned to the idle check-in control after eight seconds.
- Momentum demo Debug build: succeeded for iPhone 17 Pro simulator on iOS 26.5; load created 17 check-ins and 68 linked progress entries from four existing intentions.
- Populated Momentum walkthrough: Day showed single- and two-update cumulative states including above-target values; current/prior Week and July/August Month summaries and charts all populated through the ordinary production stores. Progress History also listed the generated dates and opened a day with readable intention totals and its linked check-in.
- Manual cleanup walkthrough: removed 86 generated data files, reported protected intention hashes unchanged, and an independent filesystem scan confirmed zero `ATTUNE_DEMO_` matches, no manifest, four intentions, and the original single intention set.
- Release-over-Debug cleanup test: Release build succeeded, preserved the simulator app container, purged all reloaded demo records on launch, kept all four intentions and the original intention set, and exposed no demo controls.
- Final simulator state: Debug build restored, demo data loaded once for Scott's visual review, and Momentum left open on the current Week chart.
- Phase 6 Debug and Release builds: succeeded for iPhone 17 Pro simulator on iOS 26.5; `git diff --check` passed.
- Phase 6 onboarding walkthrough: passed all three benefit pages, page progress, VoiceOver summaries, and completion persistence.
- Phase 6 Settings walkthrough: passed Membership, reminder defaulted on at 6 PM, Privacy & Data, Support, Debug controls, permission statuses, and external-link presentation.
- Phase 6 paywall walkthrough: passed branded Pro hierarchy, accurate Free/Pro benefits, readable unavailable state, always-visible retry/restore controls, and legal links.
- Phase 6 About/privacy walkthrough: passed product explanations, explicit user-started recording language, event-versus-calendar clarification, permission status, export explanation, and privacy/data-request links.
- Free/Pro Release walkthrough: passed today-only Momentum, locked Listening Sessions and Insights, the one-intention add gate, Pro-only export, and reminder on at 6 PM. Existing data was retained when the plan gate changed.
- Free Home no longer exposes the weekly mini-chart; it shows only today's aggregate and routes to the today-only Momentum view.
- The earlier StoreKit trial CTA verification is historical and superseded. Version 1.0 now uses a direct monthly Subscribe CTA with no introductory offer; App Store Connect/Sandbox price, purchase, and restore remain unverified.
- Release launch purged simulator-only demo history by design. The last successful Debug build was reinstalled and the removable 17-check-in/68-entry demo set was reloaded for the concurrent Momentum work.
- Final current-source Debug and Release builds succeeded after the subscription update; `git diff --check` passed. The latest Debug app is installed with demo data loaded and Momentum open.
- Production Worker tests passed 20/20 after deployment; all three live `/v2`
  synthetic task checks passed.
- The first staged iOS migration builds successfully in Debug and Release, and
  Scott confirmed physical-iPhone voice intention verification passed.
- Phase 7 simulator QA passed iPhone 17e, iPhone 17 Pro, iPhone 17 Pro Max, and
  iPad mini layouts; largest Accessibility Dynamic Type and Increase Contrast
  were also inspected. Accessibility-sized Home headers/cards now stack, core
  statuses include text/icon meaning, press/expansion animations honor Reduce
  Motion, and paywall secondary/legal controls retain 44-point touch height.
- Denied microphone access exposed Recording access is off, Open Settings, and
  Not Now. A real simulator Check-In reached 0:03, showed the recoverable speech
  failure with Try Again, and automatically returned to idle. Real offline,
  VoiceOver, audio interruption, and successful transcription remain physical
  device checks.
- Fresh generic-device Debug and Release builds passed after Phase 7 fixes.
  Worker contract tests passed 20/20. App-source compiler warnings were cleared;
  Xcode still emits only its metadata note that no AppIntents dependency exists.
- Release-link review found all four configured GitHub Pages URLs returning 404.
  The private support/privacy email, Pages deployment, App Store Connect product
  with no introductory offer, Sandbox purchase/restore, metadata, and App Privacy answers remain
  external release blockers.

## New-chat restart prompt

> Continue Attune from `ATTUNE_REMAINING_WORK.md`,
> `ATTUNE_UI_RELEASE_PLAN.md`, and `backend/openai-proxy/V2_API.md`. First
> inspect `git status` because another chat may have concurrent Momentum/UI
> edits; preserve those edits, `LegacyMomentumChartView.swift`, and the ignored
> `AI/Secrets.swift`. The hardened Worker and all three `/v2` task routes are
> deployed and live-smoke-tested. The iOS Debug build uses v2 only for voice
> intention parsing; Check-In and Listening Sessions still use v1, and Release
> remains fully on v1. Scott has completed the physical-iPhone voice-intention
> verification. Next migrate Voice Check-In behind its own Debug-only switch,
> build it, and have Scott verify real progress and mood behavior on his phone
> before migrating Listening Sessions. Do not alter persistence, “more” versus
> “total today” behavior, ambiguity handling, visible UI, or the extraction queue,
> Free/Pro rules, or UI behavior. Keep v1 as fallback until physical-device and
> TestFlight checks pass. Then continue App Attest, server-side StoreKit/D1
> usage enforcement, final AI disclosure, and Phase 7. Build, test, update the
> trackers, and stop for review before deployment or submission actions.
