# Attune Launch Steps — What YOU Still Need To Do

The app code for subscriptions is already done.

## Already done in the app (you can ignore this)

- StoreKit 2 subscription manager
- Paywall with Subscribe + Restore Purchases
- Product ID wired: `com.scottoliver.Attune.monthly`
- Free tier: **3 check-ins per day**
- Paid unlocks: unlimited check-ins, All Day recording, voice Record Intentions
- Settings → Subscription section
- Local StoreKit test file: `Attune/Products.storekit`
- OpenAI proxy code, privacy manifest, AI consent sheet, About legal links

---

## YOUR remaining checklist (do in this order)

### FIXED VALUES (use these exact strings)

| Field | Value |
|------|------|
| App name | `Attune` |
| Bundle ID | `com.scottoliver.Attune` |
| Worker folder | `/Users/scott/Desktop/Attune/Attune/backend/openai-proxy` |
| Worker name | `attune-openai-proxy` |
| Secrets file | `/Users/scott/Desktop/Attune/Attune/Attune/Attune/AI/Secrets.swift` |
| Legal links file | `/Users/scott/Desktop/Attune/Attune/Attune/Attune/App/LegalLinks.swift` |
| Subscription Group | `Attune Premium` |
| Reference Name | `Attune Monthly` |
| Product ID | `com.scottoliver.Attune.monthly` |
| Duration | `1 Month` |
| Price | `$5.99` |
| Display Name | `Attune Monthly` |
| Description | `Unlimited Attune check-ins, recording, and AI insights.` |
| Xcode project | `/Users/scott/Desktop/Attune/Attune/Attune/Attune.xcodeproj` |

---

### STEP 1 — New OpenAI key

Go to: https://platform.openai.com/api-keys

1. Revoke any old `sk-proj-...` key that was in the app
2. Create a new key
3. Copy it

Put it later into Cloudflare as `OPENAI_API_KEY`  
Do **not** put it in the iPhone app.

---

### STEP 2 — Cloudflare login + deploy

Go to: https://dash.cloudflare.com

Terminal:

```bash
cd /Users/scott/Desktop/Attune/Attune/backend/openai-proxy
npx wrangler login
npx wrangler deploy
```

Copy the Worker URL from the output.  
Example: `https://attune-openai-proxy.<subdomain>.workers.dev`

That URL becomes `proxyBaseURL`.

---

### STEP 3 — Cloudflare secrets

```bash
cd /Users/scott/Desktop/Attune/Attune/backend/openai-proxy
npx wrangler secret put OPENAI_API_KEY
```

Paste the new OpenAI key.

```bash
openssl rand -hex 32
npx wrangler secret put APP_PROXY_TOKEN
```

Paste the same hex string for `APP_PROXY_TOKEN`.  
Save that hex string — it is also `appProxyToken` in the app.

---

### STEP 4 — Fill Secrets.swift

Open:
`/Users/scott/Desktop/Attune/Attune/Attune/Attune/AI/Secrets.swift`

Put:

```swift
static let proxyBaseURL = "https://YOUR_WORKER.workers.dev"
static let appProxyToken = "YOUR_HEX_TOKEN"
```

Rules:
- no trailing slash on URL
- `appProxyToken` must match Cloudflare `APP_PROXY_TOKEN`
- do not commit this file

---

### STEP 5 — Apple Agreements / Tax / Banking

Go to: https://appstoreconnect.apple.com  
Open **Agreements, Tax, and Banking**

Complete:
- Paid Apps Agreement
- Banking
- Tax

Required before Apple will sell `$5.99/month`.

---

### STEP 6 — Create the subscription in App Store Connect

Go to: https://appstoreconnect.apple.com  
My Apps → `Attune` → Monetization → Subscriptions

Create:
1. Subscription Group name: `Attune Premium`
2. One subscription with:

| Field | Enter |
|------|------|
| Reference Name | `Attune Monthly` |
| Product ID | `com.scottoliver.Attune.monthly` |
| Duration | `1 Month` |
| Price | `$5.99` |
| Display Name | `Attune Monthly` |
| Description | `Unlimited Attune check-ins, recording, and AI insights.` |

Also in Xcode:
1. Select target `Attune`
2. Signing & Capabilities → `+ Capability` → **In-App Purchase**
3. For local testing: Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration → choose `Products.storekit`

---

### STEP 7 — Host legal pages + put URLs in the app

Host 3 public pages:
- Privacy Policy
- Terms of Use
- Support

Edit:
`/Users/scott/Desktop/Attune/Attune/Attune/Attune/App/LegalLinks.swift`

Replace the `example.com` URLs with your real ones.

Also paste into App Store Connect:
- Privacy Policy URL → App Information
- Support URL → where Apple asks for it

---

### STEP 8 — App Privacy answers

App Store Connect → `Attune` → App Privacy

Disclose at least:
- Audio Data
- User Content / transcripts
- Third-party processing: OpenAI
- Possibly wellness/mood content if asked

---

### STEP 9 — Screenshots + review notes

Upload screenshots:
- Home
- Check-in
- Paywall / Subscription
- iPhone sizes (and iPad if keeping iPad)

Review notes paste:

```
Attune records voice only when the user starts a session or check-in.
Background audio is only for an active user-started recording.
Speech may use Apple cloud speech recognition.
Transcripts are sent to OpenAI through Attune’s Cloudflare Worker proxy after the user accepts the in-app AI disclosure.
Subscription product ID: com.scottoliver.Attune.monthly ($5.99/month).
Free users get 3 check-ins/day. Subscribe unlocks unlimited check-ins, All Day recording, and voice intentions.
To demo: accept privacy sheet → start check-in → speak briefly → stop.
Also test Settings → Subscribe and Restore Purchases.
```

---

### STEP 10 — Archive → TestFlight → Submit

1. Open `/Users/scott/Desktop/Attune/Attune/Attune/Attune.xcodeproj`
2. Scheme: `Attune`
3. Destination: Any iOS Device
4. Product → Archive
5. Upload to App Store Connect
6. TestFlight: confirm AI works + purchase/restore works
7. Submit for review

---

## Quick map: where each value goes

| Value | Get from | Put in |
|------|------|------|
| New OpenAI key | platform.openai.com/api-keys | Cloudflare secret `OPENAI_API_KEY` only |
| Worker URL | `npx wrangler deploy` | `Secrets.swift` → `proxyBaseURL` |
| App token | `openssl rand -hex 32` | Cloudflare `APP_PROXY_TOKEN` **and** `Secrets.swift` → `appProxyToken` |
| Privacy / Terms / Support URLs | Your hosted pages | `LegalLinks.swift` + App Store Connect |
| Subscription product | You create it | App Store Connect with Product ID `com.scottoliver.Attune.monthly` |

Full longer handoff also lives in:
`/Users/scott/Desktop/Attune/Attune/SUBSCRIPTION_AND_APP_STORE_STEPS.md`

Also see the full purchase/account checklist:
`/Users/scott/Desktop/Attune/Attune/APP_STORE_PURCHASE_SETUP.md`
