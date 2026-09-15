# iOS App Store Release: Quick Checklist

Use this as the normal release sequence. For a first subscription submission, also follow `FIRST_SUBSCRIPTION_SUBMISSION.md` at the subscription/draft stage.

## 1. Inspect the app

Have the coding agent inspect and report:

- App name and bundle ID
- Xcode scheme and target
- Current marketing version and build number
- StoreKit Product ID and subscription code
- Entitlements and In-App Purchase capability
- Privacy permissions and `PrivacyInfo.xcprivacy`
- Legal/support URLs
- Backend or AI dependencies
- Current tests and known blockers

Do not assume old notes or portal screenshots represent current state.

## 2. Confirm the release identity

Write down the values that must agree everywhere:

```text
Bundle ID:          com.example.app
App Store version:  1.1
Build number:       3
Product ID:         com.example.app.monthly
Subscription group: Example Pro
```

The app binary has a version and build number. The subscription has a Product ID, but no build number.

## 3. Verify the code

The app must:

- request the exact Product ID configured in App Store Connect
- load and display the StoreKit-provided localized price
- support purchase, cancellation, pending, failure, and restore states
- observe transaction updates
- check current entitlements
- gate paid features from one central entitlement policy
- avoid shipping provider API keys or debug-only purchase controls

Run local tests and StoreKit tests as appropriate. Local `.storekit` success does not prove TestFlight or production behavior.

## 4. Complete external prerequisites

Before the final submission, verify as applicable:

- Apple agreements, tax, and banking are active
- Privacy Policy, Terms, and Support URLs work publicly
- The public App Description contains a functional Terms of Use/EULA link
- App Privacy is completed and published in App Store Connect
- required permissions and export compliance are accurate
- screenshots, metadata, and App Review notes are complete
- the release build has been tested on a physical device or TestFlight when purchase behavior matters

Backend or Cloudflare deployment is a separate workstream. It is not proven by an iOS build.

## 5. Configure the subscription in App Store Connect

Under **Monetization → Subscriptions**:

1. Create or verify the subscription group.
2. Create or verify the auto-renewable subscription.
3. Use the exact Product ID from the app code.
4. Set duration, price, availability, localization, tax category, and Family Sharing deliberately.
5. Add the required review screenshot and review notes.
6. Resolve missing-metadata warnings.

Do not create a duplicate product because an existing product is not immediately visible.

## 6. Set the Xcode version and create the archive

In Xcode:

1. Set the Release marketing version to the intended App Store version.
2. Increment the build number for every upload.
3. Select the correct scheme and **Any iOS Device**.
4. Choose **Product → Archive**.
5. In Organizer, verify the archive version/build, such as `1.1 (3)`.
6. Choose **Distribute App → App Store Connect → Upload**.

## 7. Wait for processing and select the build

In **TestFlight → iOS → Build Uploads**:

1. Wait until the new build says **Complete**.
2. Return to the app version under **Distribution**.
3. In the **Build** section, remove an older selected build if necessary.
4. Select the processed build matching the app version.
5. Save and verify the Build section shows the intended version/build.

Uploading a build does not automatically mean it is selected for the App Store version.

## 8. Assemble the App Review submission

For the first subscription submission, use one draft containing all required items:

- the intended iOS app version with its processed build
- the subscription group
- the subscription product

Do not submit a two-item subscription draft by itself.

## 9. Final review and submission

Before clicking **Submit for Review**, confirm:

- the draft contains the app version, group, and product
- the selected build matches the current source
- no blocking warnings remain
- App Privacy is published
- URLs and review notes are current
- The App Description includes this line when using Apple’s standard EULA:
  `Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`
- the Product ID matches the app code

Then submit once and verify the App Review page says **Waiting for Review** with the expected item count.

## 10. After submission

- Monitor App Review messages.
- Do not submit TestFlight separately unless external beta testing is wanted.
- TestFlight **Ready to Submit** is separate from App Review.
- Approval does not necessarily mean the app is already publicly available; check the release status afterward.

## If the first submission was wrong

If the app version is already Waiting for Review without the subscription:

1. Upload and process the corrected build first.
2. Remove the app version from review.
3. Wait for the removal to finish processing.
4. Select the corrected build.
5. Add the app version to the existing subscription draft.
6. Verify the draft contains all three items.
7. Submit again.

Do not delete or recreate the subscription unless Apple specifically requires it.
