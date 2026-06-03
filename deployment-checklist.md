# Trackora — Pre-Deployment Checklist

> Generated: 2026-05-16 | Branch: develop | Verdict: **Not Ready for Deployment**

Tick every box before submitting to the App Store / Play Store.

---

## 🔴 BLOCKERS (must fix before any submission)

- [ ] **Add `PrivacyInfo.xcprivacy`** to `ios/Runner/` (Apple hard-requires this since Spring 2024)
- [ ] **Change Android `applicationId`** from `com.example.trackora` → `com.michaelchia.trackora` in `android/app/build.gradle.kts`
- [ ] **Configure Android release signing** — replace the debug keystore with a real release keystore in `android/app/build.gradle.kts`
- [ ] **Fix `iosBundleId` in `lib/firebase_options.dart:66`** — currently `com.example.trackora`, must be `com.michaelchia.trackora` (Firebase will fail on iOS production)
- [ ] **Fix ShareExtension `IPHONEOS_DEPLOYMENT_TARGET = 26.2`** in `ios/Runner.xcodeproj/project.pbxproj:1394,1437,1477` — iOS 26.2 doesn't exist, likely a typo for `16.0`
- [ ] **Add `GoogleService-Info.plist` and `lib/firebase_options.dart` to `.gitignore`** — Firebase API keys are currently committed to git

---

## 🟠 HIGH PRIORITY (fix before launch)

- [ ] Tighten Firestore rules for `travelInviteCodes` and `travelEmailInvites` (currently any auth user can write)
- [ ] Restrict `travelGroups/{groupId}/members` reads to group members only
- [ ] Add image file size validation before Supabase upload (currently no limit)
- [ ] Add Firebase Crashlytics for production crash reporting
- [ ] Add Firebase Analytics (or equivalent) for usage insights
- [ ] Remove / gate 24 `dev.log()` / `print()` statements behind `kDebugMode`
- [ ] Enforce email verification on sign-up (or clearly gate features behind verified email)
- [ ] Add Supabase Storage RLS policies to restrict receipt access to the owning user

---

## 🟡 MEDIUM PRIORITY (fix soon after launch)

- [ ] Add `.limit()` or pagination to all unbounded Firestore collection listeners
- [ ] Add max image dimension resize (not just quality) before Supabase upload
- [ ] Bump `version` in `pubspec.yaml` from `1.0.0+1` to a real version before each TestFlight / Play Store upload
- [ ] Add a `DEVELOPMENT_TEAM` to `ios/Runner.xcodeproj/project.pbxproj` for distribution signing
- [ ] Configure `google-services.json` gitignore for Android

---

## 🟢 LOW PRIORITY (polish)

- [ ] Add privacy policy URL to the App Store listing and in-app settings screen
- [ ] Test all screens in dark mode on device before submission
- [ ] Verify all permission dialog strings are grammatically correct
- [ ] Test Face ID / Touch ID on real device (not simulator)
- [ ] Verify Apple Watch extension works end-to-end on real hardware
- [ ] Verify Live Activities work on iOS 16.1+ devices
- [ ] Test offline → online sync flow thoroughly
- [ ] Validate all locales (en, zh, ms) with a native speaker
- [ ] Test iPad layout (currently portrait + landscape enabled for iPad)
- [ ] Add app screenshot/preview assets for App Store listing

---

## App Store Metadata Checklist

- [ ] App name (max 30 chars): "Trackora"
- [ ] Subtitle (max 30 chars): set?
- [ ] Description (up to 4000 chars)
- [ ] Keywords (100 chars)
- [ ] Support URL set
- [ ] Privacy Policy URL set (required)
- [ ] Screenshots for all required device sizes
- [ ] App Preview video (optional but recommended)
- [ ] Age rating completed
- [ ] Content rights declaration
- [ ] Encryption declaration (already in Info.plist: `ITSAppUsesNonExemptEncryption = false`)
