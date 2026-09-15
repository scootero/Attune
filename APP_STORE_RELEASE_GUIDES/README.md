# App Store Release Guides

Use these documents in this order. They are intentionally separated so the normal release path stays short while deeper engineering and cloud guidance remains available when needed.

## Start here: `RELEASE_QUICK_CHECKLIST.md`

Use this for every iOS release. It is the short operational checklist for the order of work and the handoff between code, Xcode, App Store Connect, and manual review.

## Use for a first subscription: `FIRST_SUBSCRIPTION_SUBMISSION.md`

Use this when the app is submitting its first auto-renewable subscription of that type. It explains the special App Store Connect rule requiring the app version, subscription group, and subscription product in the same draft.

## Use only as needed: `GENERAL_RELEASE_REFERENCE.md`

This is the detailed reference for StoreKit, AI/backend and Cloudflare release gates, privacy, legal/support requirements, screenshots, testing, and reusable Claude prompts. Do not read it as one giant sequence of actions; it contains optional and project-dependent work.

## Responsibility boundaries

### Coding agent or Claude

- Inspect the repository and report the actual bundle ID, Product ID, version, build settings, StoreKit code, tests, and release blockers.
- Make approved code/configuration changes.
- Run local builds and tests.
- Prepare exact App Store Connect navigation and field values.
- Stop before signing in, submitting, purchasing, deleting, changing pricing, or making other irreversible portal changes unless explicitly authorized.

### Developer in App Store Connect/Xcode

- Sign in to Apple services.
- Review and upload the archive.
- Complete agreements, tax, banking, App Privacy, and portal metadata.
- Review the final draft.
- Click the final submission button.
- Respond to Apple review messages.

## The one rule to remember

For the first auto-renewable subscription submission, the final App Store Connect draft must contain:

1. The iOS app version with the correct processed build
2. The subscription group
3. The subscription product

If the draft has only the group and product, it is incomplete. If the app version is submitted separately, the subscription is not part of that review.
