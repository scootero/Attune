# Attune Launch Steps — Handoff for Web AI Agent

Use this document exactly. Do steps in order.

Goal:
- Launch Attune on the App Store
- One subscription only: `$4.99 / month`
- Keep OpenAI key off the iPhone app (Cloudflare Worker proxy)

Tech choice:
- Native StoreKit 2
- Not RevenueCat
- Not Stripe for in-app unlock

---

## FIXED VALUES (use these exact strings)

### App identity
| Field | Exact value |
|------|-------------|
| App name | `Attune` |
| Bundle ID | `com.scottoliver.Attune` |
| Xcode project | `/Users/scott/Desktop/Attune/Attune/Attune/Attune.xcodeproj` |
| Scheme | `Attune` |

### Cloudflare Worker
| Field | Exact value |
|------|-------------|
| Worker folder | `/Users/scott/Desktop/Attune/Attune/backend/openai-proxy` |
| Worker name | `attune-openai-proxy` |
| Secret name 1 | `OPENAI_API_KEY` |
| Secret name 2 | `APP_PROXY_TOKEN` |

### iOS Secrets file
| Field | Exact value |
|------|-------------|
| File to edit | `/Users/scott/Desktop/Attune/Attune/Attune/Attune/AI/Secrets.swift` |
| Template file | `/Users/scott/Desktop/Attune/Attune/Attune/Attune/AI/Secrets.swift.example` |
| Field 1 name | `proxyBaseURL` |
| Field 2 name | `appProxyToken` |

### Legal links file
| Field | Exact value |
|------|-------------|
| File to edit | `/Users/scott/Desktop/Attune/Attune/Attune/Attune/App/LegalLinks.swift` |
| Field 1 | `privacyPolicy` |
| Field 2 | `termsOfUse` |
| Field 3 | `support` |
| Current placeholders | `https://scootero.github.io/Attune/privacy/`, `https://scootero.github.io/Attune/terms/`, `https://scootero.github.io/Attune/support/` |

### Subscription product (App Store Connect)
| Field | Exact value |
|------|-------------|
| Subscription Group Name | `Attune Premium` |
| Subscription Reference Name | `Attune Pro Monthly` |
| Product ID | `com.scottoliver.Attune.monthly` |
| Duration | `1 Month` |
| Price | `$4.99` |
| Display Name | `Attune Pro Monthly` |
| Description | `Unlimited intentions and check-ins, Listening Sessions, Insights, Momentum history, and data export.` |

### URLs the human must visit
| Purpose | URL |
|------|-------------|
| OpenAI API keys | https://platform.openai.com/api-keys |
| Cloudflare dashboard | https://dash.cloudflare.com |
| App Store Connect | https://appstoreconnect.apple.com |

### Values the human must generate (not fixed yet)
| Value | How to get it | Where it goes |
|------|-------------|-------------|
| New OpenAI API key (`sk-...`) | Create at OpenAI API keys page | Cloudflare secret `OPENAI_API_KEY` only |
| Worker URL | Output of `npx wrangler deploy` | `Secrets.swift` → `proxyBaseURL` |
| App proxy token | `openssl rand -hex 32` | Cloudflare secret `APP_PROXY_TOKEN` AND `Secrets.swift` → `appProxyToken` |
| Privacy Policy URL | Host a public page | `LegalLinks.swift` + App Store Connect |
| Terms of Use URL | Host a public page | `LegalLinks.swift` |
| Support URL | Host a public page | `LegalLinks.swift` + App Store Connect |

---

## STEP-BY-STEP

### STEP 1 — Revoke old OpenAI key and create a new one

Go to:
- https://platform.openai.com/api-keys

Do:
1. Revoke any old `sk-proj-...` key that was ever in the iOS app
2. Create a new secret key
3. Copy the new key once

Put the new key into:
- Cloudflare only, later in STEP 4
- Secret name: `OPENAI_API_KEY`

Do NOT put the OpenAI key into:
- `Secrets.swift`
- any iOS file
- git

---

### STEP 2 — Log into Cloudflare

Go to:
- https://dash.cloudflare.com

Then run in Terminal:

```bash
cd /Users/scott/Desktop/Attune/Attune/backend/openai-proxy
npx wrangler login
```

Approve login in browser.

---

### STEP 3 — Deploy the Worker

Run in Terminal:

```bash
cd /Users/scott/Desktop/Attune/Attune/backend/openai-proxy
npx wrangler deploy
```

Copy the Worker URL from output.
Example shape:
- `https://attune-openai-proxy.<subdomain>.workers.dev`

Save that URL as:
- `proxyBaseURL`

---

### STEP 4 — Set Cloudflare secrets

Run:

```bash
cd /Users/scott/Desktop/Attune/Attune/backend/openai-proxy
npx wrangler secret put OPENAI_API_KEY
```

When prompted, paste:
- the new OpenAI key from STEP 1

Then generate token:

```bash
openssl rand -hex 32
```

Copy the hex string.

Then run:

```bash
npx wrangler secret put APP_PROXY_TOKEN
```

When prompted, paste:
- the same hex string

Save that hex string as:
- `appProxyToken`

---

### STEP 5 — Fill iOS Secrets.swift

Open file:
- `/Users/scott/Desktop/Attune/Attune/Attune/Attune/AI/Secrets.swift`

If missing, copy from:
- `/Users/scott/Desktop/Attune/Attune/Attune/Attune/AI/Secrets.swift.example`

Enter exactly:

```swift
static let proxyBaseURL = "PASTE_WORKER_URL_HERE"
static let appProxyToken = "PASTE_SAME_HEX_TOKEN_HERE"
```

Rules:
- no trailing slash on `proxyBaseURL`
- `appProxyToken` must match Cloudflare `APP_PROXY_TOKEN` exactly
- do not commit this file

---

### STEP 6 — Complete Apple paid agreement / banking / tax

Go to:
- https://appstoreconnect.apple.com
- Agreements, Tax, and Banking

Complete:
- Paid Apps Agreement
- Banking
- Tax

Required before Apple will sell the `$4.99` subscription.

---

### STEP 7 — Create the subscription product

Go to:
- https://appstoreconnect.apple.com
- My Apps → `Attune`
- Monetization → Subscriptions

Create:
1. Subscription Group
2. One subscription inside it

Enter these exact values:

| Field | Enter this |
|------|-------------|
| Subscription Group Name | `Attune Premium` |
| Reference Name | `Attune Pro Monthly` |
| Product ID | `com.scottoliver.Attune.monthly` |
| Duration | `1 Month` |
| Price | `$4.99` |
| Display Name | `Attune Pro Monthly` |
| Description | `Unlimited intentions and check-ins, Listening Sessions, Insights, Momentum history, and data export.` |

---

### STEP 8 — Host legal pages

Host 3 public HTTPS pages:
- Privacy Policy
- Terms of Use
- Support

Then open:
- `/Users/scott/Desktop/Attune/Attune/Attune/Attune/App/LegalLinks.swift`

Replace:

```swift
static let privacyPolicy = URL(string: "https://YOUR_REAL_PRIVACY_URL")!
static let termsOfUse = URL(string: "https://YOUR_REAL_TERMS_URL")!
static let support = URL(string: "https://YOUR_REAL_SUPPORT_URL")!
```

Also paste into App Store Connect:
- Privacy Policy URL → App Information
- Support URL → where Apple asks for Support URL

---

### STEP 9 — Fill App Privacy labels

Go to:
- App Store Connect → `Attune` → App Privacy

Disclose at least:
- Audio Data
- User Content / transcripts
- Third-party processing: OpenAI
- Possibly wellness / mood-related content if asked

---

### STEP 10 — Screenshots + review notes

Upload screenshots for:
- Home
- Check-in / recording
- Paywall (after subscription UI exists)
- iPhone required sizes
- iPad too if iPad support stays on

Review notes paste:

```
Attune records voice only when the user starts a session or check-in.
Background audio is only for an active user-started recording.
Speech may use Apple cloud speech recognition.
Transcripts are sent to OpenAI through Attune’s Cloudflare Worker proxy after the user accepts the in-app AI disclosure.
Subscription product ID: com.scottoliver.Attune.monthly ($4.99/month).
To demo: accept privacy sheet → start check-in/record → speak briefly → stop → wait for processing.
Also test Subscribe and Restore Purchases on the paywall.
```

---

### STEP 11 — Archive, TestFlight, submit

In Xcode:
1. Open `/Users/scott/Desktop/Attune/Attune/Attune/Attune.xcodeproj`
2. Scheme: `Attune`
3. Destination: `Any iOS Device`
4. Product → Archive
5. Distribute → App Store Connect → Upload
6. Wait for processing
7. TestFlight internal test
8. Confirm AI works through proxy
9. Confirm purchase / restore works
10. Submit for review

---

## STILL MISSING IN APP CODE

These are not implemented yet and must be added before selling the subscription:

1. StoreKit 2 support
2. Load product `com.scottoliver.Attune.monthly`
3. Paywall screen
4. Subscribe button
5. Restore Purchases button
6. Entitlement / subscription status check
7. Lock premium features behind active subscription

Recommended free vs paid (simple):
- Free: limited check-ins
- Paid (`com.scottoliver.Attune.monthly`): unlimited check-ins, recording, AI insights

---

## WHAT THE CODING AGENT CAN DO

The coding agent can confidently do:
- Add StoreKit 2 subscription code
- Build paywall UI
- Add purchase + restore
- Gate features behind subscription
- Wire product ID `com.scottoliver.Attune.monthly`
- Update docs/checklists
- Verify the Xcode project builds

The coding agent cannot do for you:
- Create/revoke OpenAI keys
- Log into Cloudflare / deploy Worker secrets
- Create App Store Connect subscription
- Complete banking/tax
- Host legal pages
- Upload screenshots / submit the app

---

## ORDER TO RUN THIS HANDOFF

1. Human/web agent: STEPS 1–5 (OpenAI + Cloudflare + Secrets.swift)
2. Human/web agent: STEPS 6–8 (Apple agreements + subscription product + legal URLs)
3. Coding agent: implement StoreKit paywall using product ID `com.scottoliver.Attune.monthly`
4. Human/web agent: STEPS 9–11 (privacy labels, screenshots, archive, TestFlight, submit)
