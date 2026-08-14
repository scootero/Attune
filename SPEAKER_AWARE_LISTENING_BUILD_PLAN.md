# Speaker-Aware Listening Sessions — Future Build Plan

## Status

Planning only. This feature is not assigned to a release phase and must not be
implemented until the feasibility gate and product/privacy decisions below are
approved.

## Product goal

During a Listening Session, distinguish the enrolled Attune user from other
voices and uncertainty. Use that distinction to prevent another person's words
from being treated as the user's intentions, commitments, events, states, or
progress.

The transcript may display simple roles:

- **You** — confidently matched to the enrolled Attune user.
- **Someone else** — confidently determined not to be the enrolled user.
- **Not sure** — overlapping, noisy, distant, or low-confidence speech.

Attune must never infer or display another person's identity. It only needs to
know whether speech confidently belongs to the enrolled user.

## Recommended v1 boundary

Speaker analysis happens on the device. Only turns confidently labeled **You**
are eligible to leave the device for Attune's existing server-owned extraction
task. Other speech is replaced with neutral sequence markers when useful:

```text
[YOU] I need to call the dentist tomorrow.
[ANOTHER_SPEAKER_PRESENT]
[YOU] Right, and I need to move the three o'clock meeting.
```

The following never leave the device in v1:

- another person's spoken words;
- a voice-enrollment recording;
- a reusable voiceprint or speaker embedding;
- audio uploaded for remote speaker recognition;
- names or guessed identities for surrounding speakers.

This boundary intentionally means v1 cannot extract a reminder or commitment
that was spoken only by someone else. Sending that person's actual words as
conversation context would be a separate future mode, because those words would
then be transmitted even if the speaker is anonymous and nothing is publicly
shared.

## Why the existing pipeline is a useful starting point

Attune already records a Listening Session in closed audio segments, queues each
segment for speech recognition, saves segment transcripts, joins the final
session transcript, runs extraction, and deletes audio according to its cleanup
flow. Speaker awareness should be an additive stage around transcription and
must preserve the existing plain-text path as the fallback.

The current speech recognizer produces plain text, not trustworthy owner-versus-
other attribution. The first gate is therefore a real on-device feasibility
spike; the production plan must not assume that a framework or model will meet
Attune's supported-device, accuracy, battery, size, and licensing requirements.

## Phase 0 — Approve the product and data contract

Before code:

- Confirm that v1 sends only **You** text to the extraction service.
- Confirm that **Someone else** and **Not sure** can never create or update an
  intention, commitment, event, state, progress entry, suggestion, or quote.
- Choose whether the local transcript shows all locally transcribed words or
  only the user's words. Default to the user's words plus neutral markers.
- Define supported devices and minimum OS based on measured model performance.
- Define retention and deletion behavior for the local voice profile, local
  transcripts, and audio.
- Review microphone, speech-recognition, App Privacy, privacy-policy, consent or
  notice, and applicable recording-law language before external testing.

Deliverable: an approved one-page data-flow table showing what is recorded,
derived, stored, transmitted, retained, and deleted.

## Phase 1 — DEBUG-only feasibility spike

Build an isolated prototype before changing the production recording pipeline:

1. Evaluate on-device speaker diarization and speaker verification candidates.
2. Use only developer-created or explicitly consented test recordings.
3. Test clean speech, background television, music, vehicle noise, distant
   speech, interruptions, overlapping speech, similar voices, and segment
   boundaries.
4. Measure owner false-attribution, owner recall, unknown rate, processing time,
   memory, application size, battery, thermal behavior, offline behavior, model
   licensing, and accessibility impact.
5. Confirm that analysis can finish before Attune's normal audio cleanup without
   blocking recovery after termination or interruption.

The prototype should prefer **Not sure** over a wrong **You** label. Accuracy
must be judged at the utterance level, not by an impressive-looking demo.

### Feasibility gate

Proceed only if representative physical-device tests show all of the following:

- fewer than 1% of non-user speech turns are falsely labeled **You**;
- at least 85% of clear, nearby user speech is retained as **You**;
- overlapping or low-confidence speech reliably falls back to **Not sure**;
- no raw audio, other-person text, or voice profile is transmitted;
- incremental battery use stays within 15% of the existing Listening Session
  baseline over a two-hour physical-device comparison;
- no thermal warning, recording interruption regression, or unbounded backlog;
- the candidate's license permits App Store distribution.

If those gates cannot be met, stop. Do not substitute confident-looking labels
for reliable ownership.

## Phase 2 — Local voice enrollment

Add an optional, explicit setup flow:

- Explain that enrollment helps Attune recognize the user's speech, not identify
  other people.
- Capture several short prompted phrases in ordinary speaking conditions.
- Derive the smallest reusable local speaker profile supported by the selected
  approach.
- Delete the enrollment audio after the profile is successfully verified.
- Protect the profile with iOS data protection and never include it in logs,
  analytics, exports, cloud sync, or server requests by default.
- Provide **Test my voice**, **Redo voice setup**, and **Delete voice profile**.
- Disable speaker-aware extraction safely when no valid profile exists.

Enrollment must be optional. Existing Listening Sessions continue through the
current plain-transcript pipeline unless the user enables the feature.

## Phase 3 — Additive speaker-turn model

Introduce a versioned, backward-compatible local model similar to:

```text
SpeakerTurn
  id
  sessionId
  segmentId
  startTime
  endTime
  text
  role: user | other | unknown
  confidenceBand: high | medium | low
  correctedRole: optional user correction
```

Requirements:

- Keep the existing `Segment.transcriptText` and `Session.finalTranscriptText`
  readable for old sessions and as a rollback path.
- Add new optional fields or a separate store; do not make existing JSON fail to
  decode.
- Preserve timestamp ordering and continuity across three-minute segment
  boundaries.
- Never persist raw voice embeddings inside session or transcript records.
- Ensure export and deletion cover speaker turns and the local voice profile.
- Store confidence bands for decisions; do not expose misleading percentages to
  users.

## Phase 4 — Processing integration

For each closed segment:

1. Produce time-aligned transcription.
2. Detect speaker turns.
3. compare each usable turn with the local enrolled-user profile.
4. Assign **You**, **Someone else**, or **Not sure** conservatively.
5. Persist local speaker turns.
6. Build a server payload containing only approved **You** text and neutral
   markers.
7. Run the existing Listening extraction task using that filtered payload.
8. Complete existing audio cleanup only after required local processing reaches
   a terminal state.

Integration rules:

- Preserve current queue idempotency, interruption recovery, and cleanup.
- Do not let speaker processing stall session completion forever.
- A failed or unavailable speaker model falls back visibly to the current
  unfiltered local transcript, but must not silently send it under the user-only
  server contract.
- Server and app schemas must reject `other` or `unknown` text in v1 payloads.
- Extraction prompts must state that only `[YOU]` statements can be treated as
  the user's evidence.
- Source quotes and recurring topics must retain speaker provenance.
- Speaker corrections may re-run local filtering/extraction only after an
  explicit user action; they must not silently alter saved intentions or
  progress.

## Phase 5 — User experience

Add calm, minimal controls rather than a technical dashboard:

- **Recognize my voice** setup in Listening Session settings.
- One clear explanation before first use.
- Transcript labels: **You**, **Someone else**, and **Not sure**.
- A simple correction action: **This was me** / **This wasn't me**.
- A session-level notice when too much speech was uncertain for reliable
  speaker-aware extraction.
- A visible indicator that only the user's matched words were analyzed.
- A direct route to delete or redo the voice profile.

Do not celebrate or imply certainty when a speaker correction has not produced
a real persisted change. Do not identify, name, count, or build profiles for
other speakers.

## Phase 6 — Safety, disclosure, and operational readiness

Before TestFlight:

- Update the in-app explanation, privacy policy, App Privacy answers, microphone
  purpose text, and export/deletion documentation to match verified behavior.
- Obtain focused legal review for recording notice or consent in intended
  markets; anonymous speakers and private storage do not automatically remove
  recording obligations.
- Verify that analytics and diagnostics contain no audio, transcript snippets,
  voice profiles, or reconstructable embeddings.
- Add a server kill switch for speaker-aware payload handling without disabling
  ordinary local session access.
- Add schema-version and payload-size limits, request validation, usage
  accounting, and privacy-safe failure metrics.
- Document dependency/model licensing, attribution, update procedure, and a
  rollback plan.

## Phase 7 — Verification and staged rollout

Automated coverage:

- legacy session decoding and rollback;
- speaker-turn ordering across segment boundaries;
- strict user-only server-payload filtering;
- rejection of `other` and `unknown` text by the v1 server contract;
- extraction cannot attribute another speaker's statement to the user;
- correction, reprocessing, deletion, export, and profile reset;
- queue recovery after force-quit, interruption, missing audio, and model error;
- feature disabled, profile absent, and unsupported-device behavior.

Physical-device matrix:

- quiet room, outdoors, car, television, music, speakerphone, and pocket/bag;
- user near and far from the phone;
- one and multiple other speakers;
- interruptions and overlapping voices;
- two-hour and representative longer sessions;
- airplane/offline mode and poor connectivity;
- supported oldest and newest device classes;
- battery, thermal, storage, memory, and background behavior.

Rollout order:

1. Internal DEBUG flag with fixed test data.
2. Developer physical-device sessions.
3. Small opt-in TestFlight group with an easy disable/reset path.
4. Review accuracy and privacy-safe operational metrics.
5. Gradual production enablement only after the feasibility thresholds continue
   to hold outside the lab.

Release must remain on the existing path until physical-device and TestFlight
evidence passes. A simulator build proves integration, not speaker accuracy,
microphone behavior, battery impact, or real-world reliability.

## Estimated difficulty and schedule

This is a medium-to-high difficulty feature because reliable ownership matters
more than ordinary multi-speaker formatting.

- Feasibility spike and evaluation harness: roughly 1–2 engineering weeks.
- Production model, enrollment, storage, queue, filtering, and UI: roughly 4–8
  additional engineering weeks if the spike succeeds.
- Physical-device evaluation, TestFlight learning, disclosure, and refinement:
  at least 2–4 calendar weeks, partly overlapping engineering.

These are planning estimates, not commitments. A model requiring remote audio,
unacceptable battery use, incompatible licensing, or frequent false ownership
would materially change the plan or make v1 a no-go.

## Explicitly deferred

- Sending another person's actual words to the server.
- Identifying, naming, remembering, or counting other people.
- Automatic creation or modification of intentions or progress from anyone's
  speech.
- Emotion, relationship, demographic, health, or identity inference from voice.
- Training a shared speaker model from customer recordings.
- Removing local audio before speaker processing is safely terminal.

## Approval checkpoint

Before implementation, return with:

1. the candidate on-device approach and license;
2. measured feasibility results on physical iPhones;
3. the exact local and server data-flow table;
4. the proposed additive schema and rollback path;
5. the user-facing setup, uncertainty, correction, and deletion flow;
6. the disclosure and recording-notice review checklist;
7. a file-level implementation plan that preserves concurrent work.

No production code should be changed until that package is reviewed and
approved.
