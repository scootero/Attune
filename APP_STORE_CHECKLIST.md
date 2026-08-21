# App Store Readiness Checklist

> Engineering history/reference. Scott's current ordered manual actions are in
> `YOUR_REMAINING_STEPS.md`; keep version 1.0 at $4.99/month with no introductory offer.

Working rules: one phase at a time; minimal diffs; update this file after each phase.

---

## Phase 0 — Checklist file

- [x] Create this checklist with phases, ASC items, and phase log

---

## Phase 1 — OpenAI proxy (security blocker)

- [x] Add Cloudflare Worker under `backend/openai-proxy/`
- [x] Rewire `OpenAIClient` to use proxy URL + app proxy token
- [x] Replace `Secrets.openAIKey` with `proxyBaseURL` + `appProxyToken`
- [x] Add `Secrets.swift.example` for clean checkouts
- [x] Deploy worker + set `OPENAI_API_KEY` and `APP_PROXY_TOKEN`
- [ ] Revoke exposed OpenAI key in OpenAI dashboard (manual)
- [x] Verify extraction / check-in AI calls succeed through proxy

---

## Phase 2 — Privacy / Info.plist plumbing

- [x] Add `PrivacyInfo.xcprivacy` (UserDefaults `CA92.1`)
- [x] Add `ITSAppUsesNonExemptEncryption = NO`

---

## Phase 3 — Consent + permission timing

- [x] First-launch AI & privacy disclosure sheet
- [x] Persist acceptance; gate OpenAI calls until accepted
- [x] Request mic/speech when user starts recording (not on Home appear)
- [x] Request notifications when enabling reminders (not on Home appear)

---

## Phase 4 — Production hygiene + About links

- [x] Hide Developer / Logs in Release (`#if DEBUG`)
- [x] Stop logging full AI response bodies in Release
- [x] About: bundle version, app icon, Privacy / Terms / Support links via `LegalLinks`

---

## Phase 5 — Manual App Store Connect

- [ ] Set app name to `Attune: Intentions Tracking`
- [ ] Set subtitle to `Are you in tune?`
- [ ] Host Privacy Policy + Terms + Support pages
- [ ] Paste live URLs into `LegalLinks.swift` (`Attune/App/LegalLinks.swift`)
- [ ] Fill App Privacy nutrition labels (Audio, User Content, OpenAI third party)
- [ ] Screenshots (iPhone; iPad if keeping iPad)
- [ ] App Review notes (background audio, demo recording, AI disclosure)
- [ ] Archive → TestFlight → Submit
- [ ] Confirm old OpenAI key revoked

Current release values are $4.99/month with no introductory trial.
Free includes one active intention and one Voice Check-In per day; use
`ATTUNE_REMAINING_WORK.md` as the controlling release tracker.

### Suggested App Review notes (copy/paste draft)

- Attune records voice only when the user starts a session or check-in.
- Background audio mode is used so an in-progress recording can continue if the app is backgrounded during an active session.
- Speech may use Apple cloud speech recognition; transcripts are sent to OpenAI via Attune’s Cloudflare Worker proxy for insights (after the user accepts the in-app AI disclosure).
- To demo: accept the privacy sheet → tap check-in or record → speak briefly → stop and wait for processing.

---

## Phase log

| Date | Phase | Notes |
|------|-------|-------|
| 2026-07-26 | 0 | Created APP_STORE_CHECKLIST.md |
| 2026-07-26 | 1 | Added Cloudflare Worker proxy; rewired OpenAIClient + Secrets. Deploy/revoke key still manual. |
| 2026-07-26 | 2 | Added PrivacyInfo.xcprivacy (UserDefaults CA92.1) and ITSAppUsesNonExemptEncryption = NO. |
| 2026-07-26 | 3 | AI disclosure sheet + consent gate; mic/speech on record start; notifications only from Settings. |
| 2026-07-26 | 4 | Release hides Logs; trimmed AI body logging; About uses bundle version + LegalLinks. |
| 2026-07-26 | 5 | Manual ASC items listed above (hosting, labels, screenshots, TestFlight) — for you. |
