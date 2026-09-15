# General iOS App Store Release Reference

This is the detailed reference for iOS release engineering, StoreKit, privacy, backend/AI services, assets, testing, App Store Connect, and reusable coding-agent prompts.

For the normal release order, use `RELEASE_QUICK_CHECKLIST.md`. For a first auto-renewable subscription submission, use `FIRST_SUBSCRIPTION_SUBMISSION.md`. This reference is not intended to be followed from top to bottom.

## The rule that prevents most release mistakes

Keep these states separate:

1. Source code is changed.
2. The app compiles or archives locally.
3. A build is uploaded to App Store Connect.
4. Apple finishes processing the build.
5. The processed build is selected for an App Store version.
6. The build is installed and tested through TestFlight.
7. App Store Connect metadata and compliance are complete.
8. The app, subscription group, and subscription product are in the same submission when required.
9. Apple approves the submission.
10. The app is actually released and visible on the App Store.

Never describe one state as proof of a later state.

## Phase 1 — Inventory the app before changing anything

Record these values before implementation:

- App name and subtitle
- Bundle identifier
- Xcode project and scheme
- Deployment target and supported device families
- Current marketing version and build number
- StoreKit product identifiers already used in code
- Backend/API endpoints
- Public privacy, terms, and support URLs
- Whether the app uses AI, analytics, microphone, speech recognition, notifications, calendar, health data, or user-generated content
- Whether the app is free, paid, or free with auto-renewable subscriptions

Search the codebase for:

- `Product` and StoreKit calls
- Product identifiers
- Entitlements and In-App Purchase capability
- `Info.plist` permission strings
- `PrivacyInfo.xcprivacy`
- hard-coded API keys or provider secrets
- release-only feature flags
- legal URL constants
- analytics and third-party SDKs
- screenshots, app icons, and marketing assets

Do not begin with a portal checklist based on guesses. First establish what the app actually does and what the current build actually contains.

## Phase 2 — Implement StoreKit 2 correctly

For a subscription app, use one source of truth for subscription state.

The minimum StoreKit 2 implementation normally includes:

- Product loading by the exact App Store product identifier
- Loading current entitlements at launch
- Observing transaction updates continuously
- Purchase handling for success, pending, cancellation, and failure
- Finishing verified transactions
- Restore purchases using `AppStore.sync()` or the selected restore flow
- A central access policy such as `SubscriptionAccessPolicy`
- A paywall showing the StoreKit-provided localized price
- A Manage Subscription link using Apple’s subscription management URL or system flow
- Graceful behavior when the product is missing, unavailable, or the network is offline

Do not use a local `.storekit` file as proof that the App Store product works. A local StoreKit configuration is for Xcode-launched simulation. TestFlight and production use App Store Connect product metadata.

### Product identity checklist

- Bundle ID in the app matches the App Store app record.
- Product ID in code exactly matches App Store Connect.
- Product is an auto-renewable subscription, not a consumable or non-consumable.
- Subscription group exists and contains the product.
- The duration cannot be changed after submission, so choose it carefully.
- The app does not silently fall back to a fake price when StoreKit has not returned a product.
- Entitlement state survives relaunch.
- Restore works independently of the original purchase button.

### Local StoreKit testing

Use a shared `.storekit` configuration for local tests only. Cover:

- product loading
- purchase success
- purchase cancellation
- pending purchase
- restore
- current entitlement
- expiration or revocation
- Free-to-Pro feature changes
- Pro-to-Free behavior after entitlement loss

Automated tests can prove policy logic. They do not prove the real App Store product, Sandbox, TestFlight, App Store review, or production billing.

## Phase 3 — Protect AI and backend credentials

Never ship a provider API key in the iOS app. A user can extract it from the binary or runtime.

For an AI-enabled app, use this pattern:

1. iOS app sends an authenticated request to your server-side gateway.
2. Cloudflare Worker or equivalent server validates the request.
3. The provider API key exists only as a server secret.
4. The server applies input limits, output limits, logging policy, and cost controls.
5. The app receives only the bounded response it needs.

### Generic Cloudflare Worker setup

Use a project-local Wrangler installation where possible. The current Wrangler command form is:

```bash
cd path/to/worker
npm run check
npx wrangler deploy --dry-run
npx wrangler login
npx wrangler deploy
npx wrangler secret put PROVIDER_API_KEY
npx wrangler secret put APP_PROXY_TOKEN
```

Generate an app proxy token locally, for example:

```bash
openssl rand -hex 32
```

Store the provider key only in the Worker secret. Store the proxy token in the Worker secret and the local ignored iOS secrets file. Never commit either value.

The Worker URL belongs in a local secrets/configuration file, not in a public source file if the project’s configuration policy treats it as environment-specific.

### Backend release gates

- Worker compiles and passes its tests.
- Dry-run packaging succeeds.
- Production deployment succeeds.
- Required secrets exist in the production environment.
- The app’s production base URL is correct.
- AI requests succeed from a release/TestFlight build.
- Provider errors are bounded and user-safe.
- Usage limits are tested before enforcement is enabled.
- Logs do not expose API keys, transcripts, full provider responses, or sensitive user content.
- Old exposed keys are revoked.

An app proxy token is not proof that a user paid for a subscription. If server-side usage limits must be subscriber-bound, add server-side Apple transaction validation and an app/device integrity mechanism. Until then, clearly distinguish on-device entitlement gating from server-side anonymous rate limiting.

## Phase 4 — Privacy, permission, and release hygiene

Before App Store submission:

- Add `PrivacyInfo.xcprivacy` for required API reasons.
- Add accurate microphone, speech-recognition, notification, calendar, health, or other permission strings.
- Ask for permission at the moment the user starts the relevant action, when practical.
- Do not request microphone, speech, or notifications merely because Home appeared.
- Explain AI processing before sending user content to a third-party provider.
- Persist consent only after the user intentionally accepts it.
- Make privacy, terms, support, and subscription information reachable in the app.
- Hide developer tools and verbose diagnostics from Release builds.
- Remove full AI response bodies, credentials, and sensitive transcript logging from Release.
- Confirm `ITSAppUsesNonExemptEncryption` and export-compliance answers are accurate.

Repository privacy text and `PrivacyInfo.xcprivacy` do not complete App Store Connect’s App Privacy questionnaire. The questionnaire must be answered and published in App Store Connect.

## Phase 5 — Public legal and support pages

Host public HTTPS pages before submission:

- Privacy Policy
- Terms of Use or EULA information
- Support page or private support contact

Verify each URL from a clean browser session and with an HTTP request. A page that exists in the repository but returns 404 publicly is not complete.

Do not send customers to a public issue tracker for private support. Use a private email address or support form.

## Phase 6 — App Store Connect account setup

In App Store Connect, complete the account gates first:

- Apple Developer membership is active.
- Correct Account Holder/Admin/App Manager access exists.
- Paid Apps Agreement is accepted and active.
- Banking information is complete.
- Tax forms are complete.
- The app record uses the correct bundle ID.
- The intended platform is selected: normally **iOS**.

“Selected platform” means the platform column in the App Store Connect submission flow. For an iPhone app, choose **iOS**. It is not a device model and it is not a build number.

## Phase 7 — Create the auto-renewable subscription

For a first subscription:

1. Open the app in App Store Connect.
2. Go to Monetization → Subscriptions.
3. Create a subscription group.
4. Create the auto-renewable product inside that group.
5. Enter the exact product ID used by the app.
6. Set duration, price, availability, localization, tax category, and Family Sharing deliberately.
7. Add a review screenshot and review notes.
8. Save and resolve any missing metadata warning.

Typical product fields:

- Reference name: internal name; it is not necessarily customer-facing.
- Product ID: permanent identifier used by StoreKit.
- Subscription duration: monthly, annual, or another supported duration.
- Price: Apple price tier/localized storefront price.
- Display name and description: customer-facing localized metadata.
- Availability: countries or regions where the product can be sold.
- Review information: how Apple can find the paywall, purchase flow, and restored entitlement.

Do not create duplicate products because a product is not immediately visible. First verify the bundle ID, product ID, subscription group, and current App Store Connect environment.

For a first auto-renewable subscription, Apple requires the subscription group and subscription product to be submitted with a new app version. The app version, group, and product belong in the same draft submission when Apple requires them together.

## Phase 8 — Prepare the app version and build

These terms are different:

- **Marketing version:** for example `1.0` or `1.1`.
- **Build number:** identifies one uploaded binary and must increase for every new upload.
- **App version record:** the App Store Connect page where the build is selected.

When source code changes after an upload:

1. Increase the build number.
2. Archive the current source.
3. Upload the archive through Xcode Organizer or Transporter.
4. Wait for Apple to process it.
5. Select that processed build in the intended App Store version.

Changing the build number in Xcode without archiving and uploading does not create a new App Store build.

Complete the app-version metadata:

- App name and subtitle
- Description
- Keywords
- Promotional text, if used
- Category
- Age rating
- Copyright
- Support URL
- Marketing URL, if used
- Privacy Policy URL
- Screenshots
- App Review notes
- Export compliance
- App Privacy publication

## Phase 9 — Screenshots and app previews

Screenshots are not the same as app previews. Screenshots are still images; app previews are optional videos.

For the App Store target used in the Pondera workflow, valid portrait screenshot sizes included:

- `1242 × 2688`
- `1284 × 2778`

Apple accepts `.jpeg`, `.jpg`, and `.png`, but images must not contain alpha/transparency. JPEG is a practical choice when App Store Connect rejects an otherwise correctly sized PNG.

Use screenshots that:

- show the real app
- preserve readable text
- avoid accidental private data
- do not imply features the build does not contain
- do not use invented claims or fake UI
- show the strongest first image, then a coherent story

Verify every exported file with an image tool before upload. Do not assume a file’s name or preview size proves its pixel dimensions.

## Phase 10 — App Privacy questionnaire

In App Store Connect → App Privacy:

1. Enter the public Privacy Policy URL.
2. Declare whether the app or third-party partners collect data.
3. Select every applicable data category.
4. For each category, answer collection purpose, linkage to the user, and tracking questions accurately.
5. Include third-party processing such as speech recognition, AI providers, analytics, or crash reporting when applicable.
6. Save all data types.
7. Publish the responses.

Do not infer “linked to the user” solely from the absence of an account. Decide from the actual identifier, retention, and association behavior of the app and its providers.

## Phase 11 — Testing in the right order

### Local Xcode

Good for:

- compilation
- unit tests
- StoreKit configuration tests
- feature policy tests

Not proof of:

- TestFlight product metadata
- Sandbox purchase behavior
- physical-device haptics or layout
- App Store review
- live Worker configuration

### Physical device

Verify permissions, microphone/speech behavior, background behavior, haptics, layout, accessibility, and real network behavior.

### Sandbox/TestFlight

Verify:

- StoreKit returns the real App Store product
- localized price appears
- purchase succeeds
- restore succeeds
- entitlement survives relaunch
- cancellation and pending states are safe
- Pro features unlock
- Free limits remain correct
- expiration/refund behavior returns access appropriately
- backend AI requests work from the uploaded build

TestFlight purchase testing uses Apple’s sandbox environment; it is not a production charge.

## Phase 12 — Assemble the draft submission

For a first subscription submission, the draft should contain:

- the intended iOS app version
- the processed build selected for that version
- the subscription group
- the subscription product

The App Store Connect warning “add an app version for the selected platform” means the draft currently contains an item such as a subscription but no iOS app-version record. It does not necessarily mean another binary must be uploaded if the correct processed build already exists.

Before clicking Submit for Review, confirm:

- no blocking warnings remain
- the selected build contains the current code
- the product ID is the one the app requests
- the subscription group is included
- the product is included
- App Privacy is published
- public URLs return successfully
- review notes explain how to test the app and subscription

## Phase 13 — After Apple approval

Approval and public availability are separate states.

- **Pending Developer Release:** the developer must release the version.
- **Ready for Sale/Distribution:** Apple has released it or is making it available.
- **Processing for Distribution:** wait for rollout.

After release, verify the public App Store page, install the production app, confirm the product loads, and test the purchase path with the appropriate production/Sandbox environment. Do not treat an approval email alone as proof that the app is visible to customers.

## Pondera example

Replace these values for another app.

| Field | Pondera value |
|---|---|
| App name | `Pondera: Intentions` |
| Subtitle | `Are you in tune?` |
| Bundle ID | `com.scottoliver.Pondera.Intentions` |
| Subscription group | `Pondera Pro` |
| Product reference name | `Pondera Pro Monthly` |
| Product ID | `com.scottoliver.Pondera.Intentions.monthly` |
| Duration | `1 Month` |
| Price target | `$4.99/month` |

Pondera’s app-side subscription policy treated the free tier and Pro tier separately. Pro access was driven by StoreKit entitlement state, while the Cloudflare Worker handled AI requests and usage controls. Those are related but not identical proofs: StoreKit entitlement proves the device’s Apple purchase state; a shared Worker token does not prove that a customer paid.

Pondera also needed:

- a Cloudflare Worker proxy so the OpenAI key was not in the iOS binary
- local StoreKit configuration for Xcode testing
- App Store Connect subscription metadata
- published privacy, terms, and support URLs
- App Privacy questionnaire responses
- a processed uploaded build
- TestFlight/Sandbox testing
- a draft containing the iOS version, subscription group, and product

## Copy-paste prompts for Claude

These prompts are deliberately evidence-bound. Claude should inspect the project and report facts instead of claiming that App Store Connect or Cloudflare work happened when it only changed local files.

### 1. Initial release audit

```text
You are auditing an iOS app for App Store release readiness.

First inspect the repository, active branch, git status, project settings, bundle identifier, scheme, deployment target, device families, StoreKit code, entitlements, Info.plist, PrivacyInfo.xcprivacy, legal URLs, backend configuration, and release flags.

Separate your report into:
1. Verified in source code
2. Verified by local build/tests
3. Requires physical-device testing
4. Requires TestFlight/Sandbox testing
5. Requires App Store Connect manual work
6. Requires Cloudflare/backend deployment
7. Unknown and needing evidence

Do not edit anything. Do not claim that an app is ready, uploaded, approved, or live unless the evidence proves that exact state. Preserve unrelated dirty-worktree changes.
```

### 2. StoreKit implementation prompt

```text
Implement or audit the subscription using native StoreKit 2.

Use these placeholders exactly:
- BUNDLE_ID: com.example.app
- PRODUCT_ID: com.example.app.monthly
- SUBSCRIPTION_GROUP: Example Pro

Before editing, locate the existing purchase manager, paywall, access policy, entitlements, StoreKit configuration, and tests. Do not create duplicate managers or product identifiers.

Requirements:
- load the product by PRODUCT_ID
- observe transaction updates continuously
- verify and finish transactions
- support purchase success, cancellation, pending, failure, restore, and current entitlements
- centralize Free/Pro policy decisions
- use StoreKit’s localized display price
- provide Manage Subscription
- add focused tests for policy and transaction-state handling
- preserve existing data and unrelated behavior

After editing, report files changed, tests run, what remains unverified on device/TestFlight, and how to revert. Do not claim App Store Connect setup is complete.
```

### 3. Cloudflare Worker proxy prompt

```text
Audit and prepare a Cloudflare Worker gateway for an iOS app that calls an AI provider.

Rules:
- the provider API key must exist only as a Worker secret
- no provider key may be present in Swift, plist, git history, logs, or the app binary
- use an app proxy token only as request authentication, not as proof of a paid subscription
- validate request size, method, content type, and origin/app token policy
- bound provider input/output and avoid logging sensitive transcript content
- preserve the current API response contract
- use the repository’s local Wrangler configuration as the source of truth

Run or prepare:
npm run check
npx wrangler deploy --dry-run
npx wrangler deploy
npx wrangler secret put PROVIDER_API_KEY
npx wrangler secret put APP_PROXY_TOKEN

Do not expose secret values. If deployment or account access is unavailable, report that as an external manual gate rather than pretending it succeeded.
```

### 4. App Store Connect setup prompt

```text
Prepare a manual App Store Connect checklist for this app. Do not log in, submit, purchase, delete, or change portal data unless I explicitly authorize that exact action.

App identity:
- APP_NAME: Example App
- BUNDLE_ID: com.example.app
- PLATFORM: iOS

Subscription:
- GROUP_NAME: Example Pro
- PRODUCT_ID: com.example.app.monthly
- DURATION: 1 Month
- PRICE_TARGET: $4.99/month

Give me the exact navigation and fields for:
1. Agreements, tax, and banking
2. App Privacy URL and published App Privacy responses
3. App version and build selection
4. Subscription group and auto-renewable product
5. Localization, price, availability, tax category, and review screenshot
6. Screenshots and review notes
7. Adding the app version, subscription group, and product to one draft submission

Distinguish what can be verified in the repository from what only App Store Connect can prove. Do not say “ready” until each external gate has evidence.
```

### 5. Screenshot preparation prompt

```text
Prepare these real app screenshots for App Store Connect.

Preserve the actual app UI, text, values, navigation, and feature meaning. Make only subtle visual cleanup. Do not invent features, marketing claims, planets, space imagery, or unrelated artwork. Remove device status-bar artifacts only if requested.

Export each file as a non-transparent JPEG at exactly:
1242 x 2688 pixels

Check every output with an image tool and report each filename, format, dimensions, and any content changes. Put the outputs in one folder with upload-order filenames.
```

### 6. Final submission gate prompt

```text
Before I click Submit for Review, perform a final evidence audit.

Use three columns:
- Verified now
- Still requires a portal/device/manual check
- Blocking if missing

Check:
- current source was archived
- build number was incremented
- uploaded build finished processing
- correct build is selected for the app version
- product ID matches code
- subscription group and product are in the draft
- screenshots have accepted dimensions and no alpha channel
- App Privacy is published
- agreements, tax, and banking are active
- privacy, terms, and support URLs work
- review notes explain purchase and restore
- TestFlight/Sandbox smoke test is complete

Do not submit anything. Tell me only the next unresolved action if one remains.
```

## Compact final checklist

### Code and build

- [ ] StoreKit product ID matches portal
- [ ] Purchase, restore, entitlement, pending, cancellation, and failure paths work
- [ ] Release build contains current code
- [ ] Build number incremented
- [ ] Archive uploaded
- [ ] Apple finished processing

### Backend and cloud

- [ ] Worker deployed
- [ ] Provider key exists only as a server secret
- [ ] Proxy token configured consistently
- [ ] Production URL is in the release configuration
- [ ] Limits and logging policy verified
- [ ] Old exposed credentials revoked

### Apple portal

- [ ] Agreements active
- [ ] Tax complete
- [ ] Banking complete
- [ ] App version created
- [ ] Correct processed build selected
- [ ] Subscription group created
- [ ] Auto-renewable product configured
- [ ] Price, duration, availability, localization, and tax category complete
- [ ] Review screenshot and notes complete
- [ ] App Privacy completed and published
- [ ] Screenshots accepted
- [ ] Draft contains the required items

### Validation

- [ ] Physical-device smoke test complete
- [ ] TestFlight/Sandbox purchase complete
- [ ] Restore verified
- [ ] Pro unlock verified
- [ ] Free limits verified
- [ ] Public legal/support URLs verified
- [ ] Submission status is understood
- [ ] After approval, app is actually released rather than waiting for developer release

## Official references

- [Apple: submit an In-App Purchase or subscription](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)
- [Apple: manage App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Apple: screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Apple: upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)
- [Apple: App Store Connect workflow](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow)
- [Cloudflare: Wrangler commands](https://developers.cloudflare.com/workers/wrangler/commands/)

Apple and Cloudflare change portal labels and requirements. Recheck the official documentation and the live portal before a new release.
