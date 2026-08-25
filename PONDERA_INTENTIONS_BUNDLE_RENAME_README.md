# Pondera: Intentions — Bundle & Brand Migration Runbook

## Objective

Permanently migrate the existing iOS app and Xcode project from **Attune** to **Pondera: Intentions**. This is a migration of the working app, not a new application or a new Xcode project.

| Identity | Current | Target |
| --- | --- | --- |
| Brand | `Attune` | `Pondera` |
| Full app name | `Attune: Intentions Tracking` | `Pondera: Intentions` |
| Bundle ID | `com.scottoliver.Attune` | `com.scottoliver.Pondera.Intentions` |

Use **Pondera** in normal UI. Use **Pondera: Intentions** where the specific product needs formal identification or distinction from future Pondera apps.

## Verified Repository Starting Point

Verified locally on August 24, 2026, before this runbook was added:

- Working tree was clean.
- Active branch was `wip/bundle-name-rename`, tracking `origin/wip/bundle-name-rename`.
- Local and remote active branch refs both pointed to `d62fffd`.
- Local and remote `backup/pre-bundle-rename` refs both pointed to checkpoint `a28e035`.
- The migration is already isolated on one branch; do not split it across parallel branches.
- Commit `d62fffd` contains 18 files of completed feature/UI work beyond the checkpoint. It is the migration baseline and must not be replaced by `a28e035`.
- Baseline validation passed: 82/82 iOS simulator tests, 36/36 Worker tests, and a Release simulator build.

Recheck before migration work:

```bash
git status --short --branch
git diff --check
git rev-parse --short backup/pre-bundle-rename
git rev-parse --short origin/backup/pre-bundle-rename
git rev-parse --short HEAD
git rev-parse --short origin/wip/bundle-name-rename
```

Stop if the tree contains important uncommitted work or the local/remote checkpoint refs do not agree. Preserve the existing checkpoint and use sensible milestone commits on the current migration branch.

## Locked Migration Decisions

- Install **Pondera** as a fresh app container. Do not attempt to read the old Attune container automatically; leave the old app installed until any desired test data is exported.
- Use **Pondera** under the app icon and throughout ordinary UI. Reserve **Pondera: Intentions** for the App Store name and formal first references.
- Replace the baked-in Attune launch video with a restrained code-native SwiftUI Pondera intro that reuses the header's existing circular mark.
- Preserve working GitHub Pages and issue URLs containing `/Attune`; change their visible labels and surrounding copy only.
- Keep the internal Xcode project, target, scheme, executable/module, test target, test Bundle ID, source types, and directories named Attune.

## Completed Targeted Audit

- The app Bundle ID exists only in the app target's Debug and Release build settings. The test Bundle ID is independent.
- `CFBundleDisplayName` is defined in the project build settings, `Info.plist`, and `en.lproj/InfoPlist.strings`; all three must agree.
- The entitlements file is empty. The project declares In-App Purchase, and the plist declares background audio.
- There is no backend Bundle-ID validation or receipt-validation service. StoreKit 2 runs on-device using the permanent Product ID.
- There is no App Attest/DeviceCheck implementation, URL scheme, deep link, extension, widget, App Intent, Keychain integration, or remote-push implementation.
- Daily reminders use local notifications and do not require the Push Notifications capability.
- The Worker and iOS client share `X-Attune-*` headers; those are an internal API contract and stay unchanged.
- The icon has no baked-in wordmark. `AttuneLaunchIntro.mp4` visibly contains Attune and must be replaced and removed from the app bundle.
- The local StoreKit configuration reports Family Sharing as false while the supplied App Store configuration says enabled; local configuration will be aligned to enabled and Apple-side state must be verified.

## Change / Retain Matrix

| Change to Pondera | Retain for compatibility/history |
| --- | --- |
| App Bundle ID in Debug and Release | Xcode project, target, scheme, module, executable, and test names |
| Home-screen name and all customer-facing app copy | `com.scottoliver.Attune.monthly` |
| Permission descriptions and local-notification titles | `Documents/Attune` storage hierarchy |
| StoreKit group/reference/display branding | `attune.*` defaults and notification identifiers |
| Current About, Privacy, Terms, Support, and public-page copy | `X-Attune-*`, Worker/D1 names, and proxy URL |
| Launch intro presentation | `ATTUNE_DEMO_`, internal type names, historical docs, and retained `/Attune` URLs |

## Apple Configuration Baseline

The following is supplied migration context and must be confirmed in Apple Developer and App Store Connect when web-side work is performed:

- Reuse the existing App Store Connect record and Apple ID.
- Keep the internal SKU `attune`.
- No build has been uploaded.
- No provisioning profiles currently exist; existing certificates are reusable.
- Current capabilities are In-App Purchase and StoreKit External Purchases or Offers.
- No App Groups, iCloud/CloudKit, Push Notifications, Sign in with Apple, or Game Center are configured.
- Existing subscription group: `Attune Premium`.
- Existing subscription: `Attune Pro Monthly`, $4.99/month, Family Sharing enabled.
- Preserve the permanent Product ID `com.scottoliver.Attune.monthly` unless a verified technical incompatibility requires otherwise.

Do not create a replacement subscription merely to remove `Attune` from its internal Product ID.

## Migration Sequence

### 1. Targeted audit

Before changing production code, briefly locate and classify:

- `com.scottoliver.Attune` and its build/signing dependencies
- entitlements and capabilities
- backend Bundle-ID or receipt validation
- StoreKit configuration
- App Attest or DeviceCheck, if actually implemented
- URL schemes, deep links, extensions, and widgets
- persistent identifiers and compatibility-sensitive values
- case-insensitive customer-facing `Attune` branding

Keep this audit narrowly focused on the rename. If the new App ID is required before signing or testing can continue, pause and request the Apple-side change.

### 2. Bundle identity

Change the existing target to `com.scottoliver.Pondera.Intentions` and update only dependencies that truly follow the Bundle ID, including applicable build settings, plist values, entitlements, signing, backend validation, receipt/App Attest/DeviceCheck configuration, URL schemes, environments, and extension identifiers.

Do not rename unrelated internal identifiers merely because they contain `Attune`.

### 3. Customer-facing branding

Search case-insensitively for `Attune`, `Attune: Intentions Tracking`, `Attune Premium`, `Attune Pro`, and `Attune Pro Monthly`, then update customer-facing copy intelligently:

- Use **Pondera** for headers, onboarding, permissions, recording copy, cards, dialogs, settings, empty states, notifications, accessibility labels, generated text, and ordinary paywall wording.
- Use **Pondera: Intentions** for formal app identification and first references in legal, privacy, support, website, and App Store metadata contexts.
- Use **Pondera Pro**, or simply **Pro** where Pondera is already obvious, for the customer-facing paid tier.

Do not force the full name into every surface, and do not alter the substantive meaning of legal or privacy language.

### 4. Website, links, and assets

Where this repository controls them, update About, Help, Support, Privacy Policy, Terms, public pages, titles, metadata, social metadata, and footer branding.

Preserve URLs containing `attune` unless a tested redirect or renamed destination exists. Replace the baked-in launch video with the approved code-native intro and remove the obsolete video from the app bundle. The existing text-free icon may remain.

### 5. Preserve compatibility

Do not blindly purge every `Attune` string. Retain old values when changing them could break upgrades, purchases, storage, or historical continuity. Likely examples include:

- StoreKit Product IDs
- UserDefaults and Keychain keys
- database or storage names
- migration and serialized identifiers
- compatibility values and historical analytics IDs
- internal Swift type names with no customer-facing impact

Any exceptional identifier migration should be justified before it is implemented.

### 6. Apple capability sanity check

Compare the app's actual implementation with its configured capabilities. Classify each finding as **Required**, **Recommended**, **Optional**, or **Unnecessary**. Specifically determine whether StoreKit External Purchases or Offers is needed, and assess only implemented needs such as App Attest/DeviceCheck, Push Notifications, Background Modes, App Intents/Siri, and Keychain-related configuration.

Do not add optional features during this migration. At most, propose one small high-value iOS improvement separately; do not implement it as part of the rebrand.

Audit classification:

- **Required:** In-App Purchase; Background Modes → audio.
- **Recommended:** none for this migration.
- **Optional later:** App Attest/DeviceCheck hardening; App Intents/Siri.
- **Unnecessary now:** StoreKit External Purchases or Offers, Push Notifications, App Groups, iCloud, Sign in with Apple, and Game Center.

Remove StoreKit External Purchases or Offers Apple-side after confirming no external-purchase program is intentionally planned.

## Verification Gate

Before declaring the migration complete:

1. Search case-insensitively for `attune` and review every remaining occurrence.
2. Categorize each as retained internal identifier, compatibility/history, ordinary English usage, or missed branding.
3. Build the app and run relevant tests.
4. Confirm StoreKit still requests `com.scottoliver.Attune.monthly`.
5. Confirm backend configuration agrees with the new Bundle ID.
6. Verify signing and Bundle-ID configuration as far as the available Apple setup permits.
7. Clearly separate automated build/test results from anything still requiring a physical iPhone or Apple web verification.

Automated gates:

```bash
git diff --check
git grep -I -i -n attune
xcodebuild -project Attune/Attune.xcodeproj -scheme Attune -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
xcodebuild -project Attune/Attune.xcodeproj -scheme Attune -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
(cd backend/openai-proxy && npm run check)
```

Inspect the built plist to confirm `CFBundleIdentifier = com.scottoliver.Pondera.Intentions` and `CFBundleDisplayName = Pondera`. Simulator QA must cover the intro, onboarding, header, About/legal links, paywall branding, and local StoreKit product loading. Physical-iPhone QA remains required for signing, microphone/speech permissions, background recording, local notifications, purchase/restore, reduced motion, and fresh-container behavior.

## Completion Report

The final migration report must cover:

- **Completed:** major technical and branding changes
- **Bundle Identity:** use of `com.scottoliver.Pondera.Intentions` and dependent changes
- **Pondera Branding:** where short and full product names are used
- **StoreKit:** retained Product ID and renamed customer-facing tier
- **Remaining Attune References:** retained occurrences and reasons
- **Apple Web Work:** remaining Developer or App Store Connect actions
- **Capabilities:** Required / Recommended / Optional / Unnecessary
- **Manual Assets:** replacements still needed
- **Verification:** build/test evidence, device-only gaps, and blockers

The finish line is a clean, working **Pondera: Intentions** app built from the existing codebase, with compatibility-sensitive identifiers preserved intentionally.

## Migration Completion Record — August 24, 2026

### Completed

- Added the migration runbook at commit `6075e53` without altering baseline feature work.
- Migrated the app identity and customer-facing SwiftUI copy at commit `8e733ee`.
- Migrated current legal, support, public-page, and actionable App Store setup copy at commit `15506d3`.
- Replaced the baked-in launch video with a code-native Pondera intro that shares the header mark and respects Reduce Motion.
- Removed `AttuneLaunchIntro.mp4`; the existing app icon is text-free and remains suitable.

### Bundle Identity

- Debug and Release use `com.scottoliver.Pondera.Intentions`.
- The built Debug and Release plists report `CFBundleDisplayName = Pondera`.
- Permission descriptions identify Pondera.
- The internal project, target, scheme, executable/module, test target, and `com.scottoliver.AttuneTests` remain unchanged intentionally.
- Simulator inspection confirmed the old Attune and new Pondera Bundle IDs have separate data containers.

### Pondera Branding

- Ordinary app UI, onboarding, notifications, accessibility copy, permissions, paywalls, and the device display name use **Pondera**.
- About, Privacy, Terms, Support, and public-page first references use **Pondera: Intentions**, then Pondera naturally.
- Working GitHub Pages and issue destinations retain `/Attune` in their URLs while visible link text identifies Pondera.

### StoreKit

- Permanent Product ID `com.scottoliver.Attune.monthly` is unchanged and covered by a regression test.
- Local group/reference/display metadata now uses `Pondera Premium` and `Pondera Pro Monthly`.
- Local Family Sharing configuration is enabled to match the supplied Apple configuration.
- App Store Connect must still verify the existing subscription's association after the app record switches to the new Bundle ID.

### Remaining Attune References

The final case-insensitive search was reviewed by category. No remaining occurrence is current customer-facing branding.

- **Internal Xcode/Swift identity:** project, target, scheme, executable/module, test bundle, `AttuneApp`, `AttuneTheme`, internal types, file headers, and `@testable import Attune`.
- **Persistence and local compatibility:** `Documents/Attune`, `attune.*` UserDefaults keys, local notification IDs, log filenames, and `ATTUNE_DEMO_` records.
- **Backend/API compatibility:** `X-Attune-*` headers, `attune-openai-proxy`, `attune-ai-usage`, proxy URLs, and related tests/docs.
- **Commerce compatibility:** `com.scottoliver.Attune.monthly`.
- **Retained destinations:** GitHub Pages and issue URLs under `/Attune`.
- **History:** older implementation summaries, handoffs, source paths, and the pre-migration portions of this runbook.
- **Asset filename only:** `Attune-Icon-1.png`; the icon itself contains no Attune text.

### Apple Web Work

1. Register the explicit App ID `com.scottoliver.Pondera.Intentions`.
2. Change the existing, never-uploaded App Store Connect record to that Bundle ID before uploading a build.
3. Confirm the existing SKU `attune`, Apple ID, subscription, and permanent Product ID remain attached.
4. Rename Apple-side subscription presentation to Pondera and verify Family Sharing remains enabled.
5. Remove StoreKit External Purchases or Offers after confirming no external-purchase program is intended.
6. Verify automatic signing/provisioning and sandbox product loading with the new App ID.

### Capability Recommendations

- **Required:** In-App Purchase; Background Modes → audio.
- **Recommended:** none for this migration.
- **Optional later:** App Attest/DeviceCheck; App Intents/Siri.
- **Unnecessary now:** StoreKit External Purchases or Offers, Push Notifications, App Groups, iCloud, Sign in with Apple, and Game Center.

### Verification Evidence

- `git diff --check`: passed.
- iOS Debug simulator tests: 84 passed, 0 failed, 0 skipped on iPhone 17 Pro / iOS 26.5.
- Worker `npm run check`: TypeScript passed; 36 tests passed across 3 files.
- Release simulator build with store validation: passed.
- Built Debug and Release identity: `com.scottoliver.Pondera.Intentions` / `Pondera`.
- Product ID regression: passed for `com.scottoliver.Attune.monthly`.
- Simulator visual QA: Pondera intro and first onboarding screen rendered correctly; the transition completed.
- Built app asset check: no `AttuneLaunchIntro` resource remains.

### Still Requires Manual Verification

- Apple Developer/App Store Connect work listed above was not performed by this code migration.
- Physical-iPhone signing, display name, microphone/speech permissions, background recording, local notification actions, Reduce Motion feel, purchase, and restore remain unverified.
- Live/sandbox StoreKit product availability under the new App ID remains unverified. Xcode CLI continues to emit the pre-existing `_storeKitConfigurationFileReference` scheme warning even though builds and tests pass and the scheme still references `Products.storekit`.
- The public pages were updated in the repository but were not deployed separately.
