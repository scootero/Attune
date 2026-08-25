# Pondera: Intentions App Store Purchase Setup

> Reference only. The current controlling manual checklist is
> `YOUR_REMAINING_STEPS.md`. The Worker deployment, app secrets wiring, In-App
> Purchase capability, and local StoreKit configuration are already complete.
> Version 1.0 is $4.99/month with **no introductory offer or free trial**; do
> not repeat completed deployment/key steps solely because they appear below.

This is the full checklist to make Pondera purchasable with one subscription.

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

## Accounts you must have

1. Apple Developer Program (active paid membership)
2. App Store Connect access
3. Cloudflare account
4. OpenAI account

## Remaining setup you must do

### 1) Agreements, Tax, Banking
- Go to App Store Connect → Agreements, Tax, and Banking
- Accept Paid Apps agreement
- Add bank account
- Complete tax forms

### 2) Confirmed subscription product
- App Store Connect now has group `Pondera Pro` and this product:
  - Reference Name: `Pondera Pro Monthly`
  - Product ID: `com.scottoliver.Pondera.Intentions.monthly`
  - Duration: `1 Month`
  - Price: `$4.99`
  - Display Name: `Pondera Pro Monthly`
  - Description: `Unlimited intentions and check-ins, Listening Sessions, Insights, Momentum history, and data export.`
  - Family Sharing: enabled

### 3) Cloudflare/OpenAI proxy setup
- Revoke old OpenAI key, create new key
- Deploy worker:

```bash
cd /Users/scott/Desktop/Pondera/Pondera/backend/openai-proxy
npx wrangler login
npx wrangler deploy
npx wrangler secret put OPENAI_API_KEY
openssl rand -hex 32
npx wrangler secret put APP_PROXY_TOKEN
```

- Fill local secrets file: `/Users/scott/Desktop/Pondera/Pondera/Pondera/Pondera/AI/Secrets.swift`

```swift
static let proxyBaseURL = "https://YOUR_WORKER.workers.dev"
static let appProxyToken = "YOUR_HEX_TOKEN"
```

### 4) Legal URLs
- Host Privacy Policy, Terms, Support pages
- Put links in `/Users/scott/Desktop/Pondera/Pondera/Pondera/Pondera/App/LegalLinks.swift`
- Put Privacy + Support URLs in App Store Connect App Information

### 5) Privacy + listing
- Fill App Privacy questionnaire (Audio, User Content, OpenAI third party)
- Upload screenshots (include paywall)
- Add review notes describing subscription unlocks and restore path

### 6) Testing and submit
- Simulator local test uses `Products.storekit` (already wired in shared scheme)
- Device testing uses Sandbox tester in App Store Connect
- Archive, upload, TestFlight, then submit

## Quick smoke test before submit

- Subscribe works
- Restore works
- Manage Subscription opens
- Free cap blocks after one Voice Check-In per day
- Paid unlocks blocked features
- AI still works through proxy
