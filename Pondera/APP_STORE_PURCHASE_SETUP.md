# Pondera: Intentions App Store Purchase and Release Setup

This is the release gate for making Pondera purchasable with one auto-renewable
subscription. Repository checks and local StoreKit tests do not prove App Store
Connect, Sandbox, TestFlight, signing, or production status.

## Status snapshot — August 25, 2026

| Area | Current evidence | Release status |
| --- | --- | --- |
| StoreKit implementation | Product load, purchase, restore, transaction updates, and current-entitlement checks are present | Ready for local/sandbox testing |
| Product identity | Bundle `com.scottoliver.Pondera.Intentions`; product `com.scottoliver.Pondera.Intentions.monthly` | Matches repository and recorded App Store Connect setup |
| Local StoreKit | Shared `Products.storekit` configuration at $4.99/month; automated product-load test plus manager purchase/restore state tests | Verified locally; interactive purchase still required |
| Feature access | Free/Pro decisions are centralized in `SubscriptionManager` and `SubscriptionAccessPolicy` | Verified by unit tests; visual/device sweep still required |
| Public legal links | Privacy, Terms, and Support return HTTP 404 | **Blocking: deploy before TestFlight review** |
| Support contact | Local support page still says a private email will be added | **Blocking: choose and publish a private support address/form** |
| App Store Connect | Product creation was recorded previously, but the portal was not authenticated for the August 25 audit | **Manual verification required** |
| Cloudflare AI usage | Worker compiles/tests and dry-run packaging succeeds; usage enforcement is still `shadow` | TestFlight verification required before switching to `enforced` |
| Server-side Apple entitlement | Not implemented; the app uses StoreKit 2 on-device entitlement checks | Acceptable for on-device UI access; required before treating the Worker allowance as securely subscriber-bound |
| iOS availability | App deployment target is iOS 26.2 and device family is iPhone only | **Product decision required before release** |

## What is already done in code

- StoreKit 2 purchase, restore, and entitlement checks
- Paywall UI with Subscribe/Restore
- Product ID wired: `com.scottoliver.Pondera.Intentions.monthly`
- Feature gating: free = one active intention and one Voice Check-In per day; Pro adds more intentions, unlimited check-ins, Listening Sessions, Insights, Momentum history, voice setup, and export
- In-App Purchase capability wiring in project
- Entitlements file wired in Debug + Release
- Shared Xcode scheme with `Products.storekit` local test config
- Manage Subscription button in Settings

## Fixed values (use exactly)

- App Store name: `Pondera: Intentions`
- Subtitle: `Are you in tune?`
- Bundle ID: `com.scottoliver.Pondera.Intentions`
- Team ID: `BLAUCQ8H26`
- Subscription Group: `Pondera Pro`
- Product Reference Name: `Pondera Pro Monthly`
- Product ID: `com.scottoliver.Pondera.Intentions.monthly`
- Duration: `1 Month`
- Price: `$4.99`
- Display Name: `Pondera Pro Monthly`
- Description: `Unlimited intentions and check-ins, Listening Sessions, Insights, Momentum history, and data export.`

## Accounts and access required

1. Apple Developer Program (active paid membership)
2. App Store Connect access
3. Cloudflare account
4. OpenAI account

## Release-blocking setup

### 1) Agreements, Tax, Banking
- Go to App Store Connect → Agreements, Tax, and Banking
- Accept Paid Apps agreement
- Add bank account
- Complete tax forms
- Confirm the Paid Apps agreement shows **Active**. Apple requires an active
  agreement for Sandbox In-App Purchase testing.

### 2) Verify the recorded subscription product in App Store Connect
- App Store Connect was previously recorded as having group `Pondera Pro` and:
  - Reference Name: `Pondera Pro Monthly`
  - Product ID: `com.scottoliver.Pondera.Intentions.monthly`
  - Duration: `1 Month`
  - Price: `$4.99`
  - Display Name: `Pondera Pro Monthly`
  - Description: `Unlimited intentions and check-ins, Listening Sessions, Insights, Momentum history, and data export.`
  - Family Sharing: enabled
- Also verify:
  - Status has no missing metadata warning
  - United States and every intended launch storefront are available
  - Tax category is selected
  - English (U.S.) group localization is present and user-facing
  - Review screenshot is uploaded
  - Review notes explain where to open the paywall, how to restore, and what Pro unlocks
  - The subscription is added to the first app version's In-App Purchases section

Apple requires the first auto-renewable subscription and first subscription
group to be submitted with a new app version.

### 3) Cloudflare/OpenAI proxy setup
- Revoke old OpenAI key, create new key
- Deploy worker:

```bash
cd /Users/scott/Desktop/Attune/Attune/backend/openai-proxy
npm run check
npx wrangler deploy --dry-run
npx wrangler login
npx wrangler deploy
npx wrangler secret put OPENAI_API_KEY
openssl rand -hex 32
npx wrangler secret put APP_PROXY_TOKEN
```

- Fill the gitignored local secrets file:
  `/Users/scott/Desktop/Attune/Attune/Pondera/Pondera/AI/Secrets.swift`

```swift
static let proxyBaseURL = "https://YOUR_WORKER.workers.dev"
static let appProxyToken = "YOUR_HEX_TOKEN"
```

### 4) Legal URLs
- Deploy the repository's `docs/` directory so these exact URLs return HTTP 200:
  - `https://scootero.github.io/Attune/privacy/`
  - `https://scootero.github.io/Attune/terms/`
  - `https://scootero.github.io/Attune/support/`
- Keep the same links in
  `/Users/scott/Desktop/Attune/Attune/Pondera/Pondera/App/LegalLinks.swift`
- Put Privacy + Support URLs in App Store Connect App Information
- Replace the public GitHub issue tracker with a private support email or form
  before submission so customers are not asked to post sensitive material publicly.

### 5) Privacy + listing
- Fill App Privacy questionnaire (Audio, User Content, OpenAI third party)
- Upload screenshots (include paywall)
- Add review notes describing subscription unlocks and restore path

### 6) Test in four distinct layers

1. Automated simulator tests: local product load, manager purchase/restore
   states, and feature policy.
2. Xcode StoreKit UI test: set Debug `Subscription Access` to `System`; buy,
   restore, cancel, relaunch, expire/refund, and confirm Free/Pro transitions.
3. Physical-device Sandbox test: use a Sandbox Apple Account on a
   development-signed build; test purchase, restore on a second install/device,
   renewal, expiry, billing retry, interruption, and Family Sharing.
4. TestFlight test: confirm the real App Store Connect product loads, the
   localized price is shown, purchase/restore work, and every paid feature
   unlocks. TestFlight purchases remain in Apple's sandbox.

Only after these pass: archive, upload, attach the subscription to the app
version, add both the app and subscription for review, then submit.

### 7) Backend cost-control gate

- The app currently embeds a shared proxy token. Treat it as an app credential,
  not proof of a paid subscription.
- Keep `USAGE_LIMIT_MODE=shadow` while validating the updated client in
  TestFlight; then change it to `enforced` and re-run all AI flows before release.
- Before promising that the monthly AI allowance is securely tied to a paying
  subscriber, implement server-side Apple transaction validation plus App
  Attest (or another per-install integrity mechanism). Until then, the on-device
  StoreKit gate is the source of truth for UI access and Worker limits are only
  per anonymous installation.

## Required smoke test before submit

- Subscribe works
- Restore works
- Manage Subscription opens
- Free cap blocks after one Voice Check-In per day
- Paid unlocks blocked features
- AI still works through proxy
- Relaunch while subscribed still unlocks Pro
- Expiry/refund returns future feature access to Free without deleting data
- Purchase pending and cancellation leave the app usable
- Localized price comes from StoreKit; no fallback price is used during purchase
- Privacy, Terms, Support, and Apple EULA links all return HTTP 200
