# Pondera App Store Resubmission Checklist

Last updated: 2026-09-09

Purpose: one high-level checklist for resolving Apple’s Guideline 2.1 rejection and resubmitting Pondera: Intentions. Do not submit until every required item is checked.

## Current focus: Pondera Pro StoreKit

- [x] Code audit: the shared `Pondera` scheme runs Debug with `Products.storekit` attached for local StoreKit testing.
- [x] Code audit: the scheme archives with Release; Debug-only subscription controls are excluded from Release by `#if DEBUG`.
- [x] Code audit: local StoreKit product ID and app product ID match `com.scottoliver.Pondera.Intentions.monthly`; local price is `$4.99`.
- [ ] Run the local StoreKit test; current Mac session cannot access an iOS Simulator runtime, so this is not yet verified here.
- [ ] Confirm the Release/TestFlight build does not show Debug test mode and loads the App Store product.
- [ ] Confirm `Pondera Pro Monthly` is the product used by the app: `com.scottoliver.Pondera.Intentions.monthly`.
- [ ] Leave the old `Attune Premium` product untouched unless separately reviewed.
- [ ] Keep the optional 1024×1024 subscription **Image** field separate from the required App Review screenshot.
- [ ] Capture a clean Pondera Pro paywall screenshot with the price and purchase control visible; no debug label and no “temporarily unavailable” error.
- [ ] Complete/save Pondera Pro Review Information; verify the Review Information → Screenshot field is populated.
- [ ] Verify Family Sharing is disabled if Pondera should not be shareable with a family group.
- [ ] Test the purchase UI with Xcode StoreKit Testing first for speed.
- [ ] Test the real App Store product data in Apple Sandbox using a development build or TestFlight build; no real purchase is required.
- [ ] Confirm the release/TestFlight build loads the product successfully and does not show “Pondera Pro is temporarily unavailable.”
- [ ] Archive/upload a new Release build with an incremented build number.
- [ ] After the new build is available, use **Add for Review** for Pondera Pro Monthly and include it with the app version submission.
- [ ] Manually review everything, then manually Reply/Submit/Resubmit.

## App Review information already prepared

- [x] Purpose, audience, setup, external services, regions, account/login, private content, and regulated-service statements drafted.
- [x] Physical-device walkthrough recording created.
- [ ] Reattach the walkthrough recording to the final App Review reply if Apple’s submission flow requires it.
- [ ] Copy the final approved review explanation into App Review Information → Notes.

## Final App Store Connect checks

- [ ] Confirm the selected build is the new Release build, not the rejected build 1.
- [ ] Confirm Pondera Pro Monthly and the app version are in the same draft submission.
- [ ] Confirm Pondera Pro metadata: product ID, one-month duration, $4.99 US price, availability, localization, review notes, and screenshot.
- [ ] Confirm the app’s Privacy Policy and Support URLs are live.
- [ ] Confirm App Privacy declarations match actual audio/transcript/AI processing.
- [ ] Confirm screenshots show the actual app and contain no debug/test-only UI.
- [ ] Confirm no placeholder, unavailable, or misleading subscription text appears in the Release/TestFlight build.
- [ ] Confirm the app’s review contact information and Notes are current.

## Deferred after approval

- [ ] Decide whether to clean up the unused Attune Premium subscription group; do not delete it during this rejection repair.
- [ ] Design official Apple offer codes for time-limited free/discounted access for friends or family. Lifetime access is not provided by a normal subscription offer code.
- [ ] Revisit any promotional subscription image or App Store promotion separately from the required review screenshot.

## Submission gate

The app is ready to resubmit only when the Release/TestFlight build successfully loads Pondera Pro, the required subscription screenshot is saved, Pondera Pro Monthly is added for review with the new app build, and the final reply/submit actions have been manually reviewed.
