# Navi iOS + TestFlight Checklist

Use this checklist on the Mac that will build and upload Navi to Apple.

## 1. Account Ownership

- The Apple Developer account that signs the app owns the iOS app record, Bundle ID, certificates, TestFlight builds, and App Store Connect listing.
- If this is a friend-owned Apple Developer account, they will need to upload future iOS builds unless they add you to their App Store Connect team with enough permissions.
- Recommended roles for ongoing updates:
  - **Developer**: can build/sign with the team in Xcode.
  - **App Manager** or **Admin**: can manage TestFlight builds, testers, metadata, and releases.

## 2. Mac Setup

Install on the Mac:

```bash
xcode-select --install
```

Then install:

- Xcode from the Mac App Store
- Flutter SDK
- CocoaPods
- Apple Transporter, optional but useful

Verify:

```bash
flutter doctor
sudo xcode-select --switch /Applications/Xcode.app
sudo xcodebuild -runFirstLaunch
```

## 3. Repo Setup

Clone or pull the repo:

```bash
git clone <repo-url>
cd navi_personal
flutter pub get
cd ios
pod install
cd ..
```

## 4. Apple Developer Setup

In Apple Developer:

1. Go to **Certificates, IDs & Profiles**.
2. Create or select the app Bundle ID.
3. Use a permanent Bundle ID, for example:

   ```text
   com.<account-or-org>.navi
   ```

4. Enable capabilities:
   - **HealthKit**
   - **Push Notifications**, if Firebase notifications/check-ins will be used

## 5. Firebase iOS Setup

In Firebase Console (under Cole's google account):

1. Open project `project-bc878e6c-6f53-4f24-88a`.
2. Add an iOS app using the exact same Bundle ID.
3. Download `GoogleService-Info.plist`.
4. Place it here:

   ```text
   ios/Runner/GoogleService-Info.plist
   ```

5. If push notifications are enabled:
   - Create an APNs Auth Key in Apple Developer.
   - Upload it in Firebase Console under Cloud Messaging Apple app configuration.

## 6. Xcode Project Setup

Open:

```bash
open ios/Runner.xcworkspace
```

In Xcode:

1. Select **Runner**.
2. Set the Bundle Identifier to the registered Bundle ID.
3. Set **Team** to the Apple Developer team.
4. Enable **Automatically manage signing**.
5. Go to **Signing & Capabilities**.
6. Add/check:
   - **HealthKit**
   - **Push Notifications**, if used

The repo already includes HealthKit permission strings in `ios/Runner/Info.plist`.

## 7. Run On A Physical iPhone

Plug in the iPhone and run:

```bash
flutter run
```

Smoke test on the phone:

- Sign in.
- Save a journal entry.
- Confirm cloud sync works.
- Open Today and Insights.
- Open Settings.
- Confirm Apple Health appears.
- Tap Apple Health sync and grant Health permissions.
- Confirm sleep/heart metrics sync without errors.
- Confirm research packet upload button appears only when research/data-sharing is enabled.

## 8. Build For TestFlight

Increment the build number each upload:

```bash
flutter build ipa --release --build-name 1.0.0 --build-number 1
```

For the next upload:

```bash
flutter build ipa --release --build-name 1.0.0 --build-number 2
```

## 9. Upload Build

Upload using one of:

- Xcode Organizer
- Apple Transporter

The generated IPA is usually under:

```text
build/ios/ipa/
```

## 10. TestFlight Setup

In App Store Connect:

1. Create the app record if it does not exist.
2. Open the app.
3. Go to **TestFlight**.
4. Add beta app information.
5. Add internal testers first.
6. Upload/select the build.
7. For external testers:
   - Create an external tester group.
   - Add the build.
   - Submit for Apple beta review.
   - After approval, invite testers by email or public link.

## 11. Beta Notes

Use clear TestFlight notes:

```text
Navi is a personal journaling and wellbeing insights beta. It is not emergency care, crisis monitoring, diagnosis, treatment, or medical advice. Please test journal save/sync, Today, Insights, Settings, Apple Health sync, and data export/recovery flows.
```

## 12. Future iOS Updates

For every iOS update:

1. Pull latest repo changes.
2. Run:

   ```bash
   flutter pub get
   cd ios
   pod install
   cd ..
   flutter analyze
   flutter test
   ```

3. Increment `--build-number`.
4. Build the IPA.
5. Upload to App Store Connect.
6. Assign the build to TestFlight testers.

