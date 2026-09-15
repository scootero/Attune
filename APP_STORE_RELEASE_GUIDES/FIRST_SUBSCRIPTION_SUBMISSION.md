# First iOS App Submission with an Auto-Renewable Monthly Subscription

This is a reusable first-submission workflow for an iOS app that includes one auto-renewable monthly subscription.

The central rule is:

> The first subscription product, its subscription group, and the app version must be submitted together in one App Store Connect draft.

The final submission should contain exactly these three kinds of items:

1. The iOS app version and its correct processed build
2. The subscription group
3. The subscription product

## 1. Decide the release identity first

Write these values down before changing anything:

| Item | Example |
|---|---|
| App name | Pondera: Intentions |
| Bundle ID | `com.example.app` |
| App Store version | `1.1` |
| Build number | `3` |
| Subscription group | `Pro` |
| Subscription display/reference name | `Pro Monthly` |
| Subscription Product ID | `com.example.app.monthly` |
| Duration | 1 Month |
| Price | Set in App Store Connect |

The app version and build number belong to the app binary. The subscription does not have a build number.

## 2. Configure the subscription in the app code

Before archiving, make sure the app uses the exact App Store Connect Product ID:

```swift
let productID = "com.example.app.monthly"
```

Verify that the code supports:

- Loading the product
- Displaying the localized StoreKit price
- Purchasing the subscription
- Restoring purchases
- Observing transaction updates
- Checking current entitlements
- Unlocking Pro features only while entitled
- Returning to the free state after expiration or refund

Do not hardcode a different Product ID, price, or duration in the release code.

## 3. Set the Xcode version and build number

In Xcode, select the app target and set:

```text
Marketing Version: 1.1
Current Project Version: 3
```

Check both **Debug** and **Release** if the project displays separate columns. The important value for App Store Connect is **Release** because Archive uses Release.

Before archiving, verify:

- The bundle ID is the intended App Store Connect app
- The target is the intended app target
- The Product ID in code is the intended subscription Product ID
- The Release version and build number are correct

## 4. Test before uploading

Run the appropriate checks before creating the release archive:

1. Build and automated tests.
2. Local Xcode StoreKit testing, if available.
3. Physical-device testing of the purchase screen, restore flow, and Pro unlocks.
4. TestFlight or Sandbox testing with the real App Store Connect product.

At minimum, verify that the release/TestFlight build loads the product and does not show an unavailable-product error.

Local `.storekit` testing proves only the local test environment. It does not prove that the App Store Connect product, Sandbox, TestFlight, or production configuration works.

## 5. Create the App Store Connect subscription

In App Store Connect:

1. Open the app.
2. Go to **Monetization → Subscriptions**.
3. Create the subscription group.
4. Create the monthly subscription inside that group.
5. Enter the exact Product ID used by the app.
6. Set the duration, price, availability, localization, and description.
7. Complete any required tax, agreement, and banking setup.
8. Add the required App Review information and screenshot.

The first subscription and its group should show a review-ready state, such as **Ready for Review**. Do not create duplicate groups or products if the intended Product ID already exists.

## 6. Upload the correct app build

In Xcode:

1. Select the intended app scheme.
2. Select **Any iOS Device** or a physical iPhone destination.
3. Choose **Product → Archive**.
4. In Organizer, verify the archive says the intended version and build, for example `1.1 (3)`.
5. Choose **Distribute App → App Store Connect → Upload**.
6. Complete validation and upload.

In App Store Connect → **TestFlight → iOS → Build Uploads**, wait until the build says **Complete**.

The uploaded build must match the app version:

```text
App Store version: 1.1
Uploaded build: 1.1 (3)
```

Do not proceed with an older build such as `1.0 (2)` when the App Store version is `1.1`.

## 7. Attach the correct build to the app version

In App Store Connect → **Distribution → iOS App 1.1**:

1. Scroll to the **Build** section.
2. Remove an older or incorrect selected build if necessary.
3. Click the **+** button to add a build.
4. Select the processed build matching the app version, such as `1.1 (3)`.
5. Click **Done** and **Save**.
6. Confirm the page shows the correct build and version.

Uploading a build does not automatically mean that App Store Connect selected it for the app version. Always verify the Build section.

## 8. Prepare the App Review draft

First, add the subscription product and group for review:

1. Open the subscription product.
2. Click **Add for Review**.
3. Add it to an existing draft or create one draft for this submission.
4. Ensure the subscription group is included with the first subscription.

Then add the app version:

1. Return to **Distribution → iOS App 1.1**.
2. Confirm the correct build is attached.
3. Click **Add for Review**.
4. Choose the existing subscription draft.
5. Do not create a separate second draft.

The draft must show:

```text
Versions: iOS 1.1
Items: 3
```

The three items must be:

- iOS App 1.1 with the correct build
- The subscription group
- The subscription product

If the draft says **Unable to Submit for Review — add an app version**, the subscription items are present but the app version has not been added yet.

## 9. Important recovery rule when an app is already Waiting for Review

If the app version was submitted without the subscription:

1. Do not submit the two-item subscription draft by itself.
2. Do not recreate the subscription.
3. Upload and process the corrected build first.
4. On the app version page, choose **remove this version from review**.
5. Wait until the removal finishes processing.
6. Attach the correct build to the app version.
7. Add the app version to the existing subscription draft.
8. Confirm the draft contains all three items.

Removing a submitted version restarts App Review. It is a deliberate correction, not a deletion of the app or subscription.

## 10. Final checks before submitting

Confirm all of the following:

- The app version is correct.
- The selected build matches the app version.
- The subscription Product ID matches the release code.
- The subscription group and product are in the same draft as the app version.
- The subscription review screenshot and notes are present.
- App Review notes explain how to reach the subscription screen and restore purchases.
- Required App Privacy information is complete and published.
- Privacy, Terms, and Support URLs are live.
- The public App Description includes a functional Terms of Use/EULA link. When
  using Apple’s standard EULA, add:
  `Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`
- Required app metadata and screenshots are complete.
- No debug-only controls, unavailable-product messages, or test labels appear in the release build.

## 11. Submit and wait

When the draft shows all three items:

1. Review the complete draft.
2. Click **Submit for Review**.
3. Confirm the submission.
4. Verify the App Review page shows **Waiting for Review** and **3 items submitted**.

The TestFlight status **Ready to Submit** is separate. It refers to optional external beta testing and does not mean the App Store submission is incomplete.

After submission, monitor App Review messages. Do not make pricing, availability, deletion, or release changes while waiting unless there is a specific reason to do so.

## Short version

```text
Set Product ID in code
→ configure group and subscription in App Store Connect
→ set Xcode Release version/build
→ test
→ archive
→ upload
→ wait for processing
→ select the matching build on the app version
→ add subscription and group to a draft
→ add the app version to that same draft
→ verify 3 items
→ submit once
→ wait for review
```
