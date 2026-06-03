# Trackora — App Store Readiness Report

> Generated: 2026-05-16 | Branch: develop

---

## iOS App Store Status: ❌ NOT READY

### Hard Blockers

| # | Issue | Severity | Status |
|---|-------|----------|--------|
| 1 | `PrivacyInfo.xcprivacy` missing | CRITICAL | ❌ |
| 2 | Firebase API keys in git | CRITICAL | ❌ |
| 3 | No crash reporting | CRITICAL | ❌ |

### Permission Declarations (Info.plist)

| Permission | Key | String | Status |
|-----------|-----|--------|--------|
| Camera | `NSCameraUsageDescription` | "Trackora uses the camera to attach receipts to expenses." | ✅ |
| Photo Library | `NSPhotoLibraryUsageDescription` | "Trackora needs access to your photos to attach receipts to expenses." | ✅ |
| Face ID | `NSFaceIDUsageDescription` | "Trackora uses Face ID to let you sign in quickly and securely." | ✅ |
| Microphone | Not declared | N/A — not used | ✅ |
| Location | Not declared | N/A — not used | ✅ |
| Contacts | Not declared | N/A — not used | ✅ |

### Sign In with Apple Compliance

The app uses Google Sign-In (`google_sign_in: ^6.2.2`). App Store rule: if an app offers any third-party or social sign-in, Sign In with Apple must also be offered.

**Status: ✅ COMPLIANT** — `sign_in_with_apple: ^6.1.4` is included and the auth service implements `signInWithApple()`. Verify it appears on the login/welcome screen UI.

### Encryption Declaration

`ITSAppUsesNonExemptEncryption = false` in Info.plist. **✅ Correct** — the app uses standard HTTPS/TLS, which is exempt.

### iOS Deployment Target

Podfile sets `platform :ios, '13.0'`. **✅ Acceptable** — iOS 13 is a reasonable minimum. Note: `local_auth` and `sign_in_with_apple` require iOS 12+, so this is fine.

### App Version

`pubspec.yaml`: `version: 1.0.0+1`

**⚠️ Action required:** Must increment the build number (`+1` → `+2`, etc.) for every TestFlight and App Store upload. The version string `1.0.0` is fine for launch.

### Orientation

Info.plist supports portrait + both landscape modes. iPad supports all 4 orientations. If your UI is not tested in landscape mode, consider restricting to portrait-only until you verify.

### URL Schemes

Two URL schemes registered:
1. `trackora` — deep links. ✅
2. `com.googleusercontent.apps.957463431763-tvksvin07tht16fgcf3pljvbrjhle3ln` — Google Sign-In reverse client ID. ✅

### Live Activities

`NSSupportsLiveActivities = true` in Info.plist. ✅ Required if using Live Activities.

### `debugShowCheckedModeBanner`

Set to `false` in `main.dart`. ✅

### WebView Usage

No `webview_flutter` or `InAppWebView` found. Uses `url_launcher` only (opens Safari). **✅ No WebView review risk.**

### App Icons

`flutter_launcher_icons` configured in `pubspec.yaml` with `remove_alpha_ios: true` (required for iOS). **✅** — run `dart run flutter_launcher_icons` before the release build to regenerate.

### Missing from App Store Listing

- [ ] Privacy Policy URL (required for apps with accounts)
- [ ] App screenshots for all required sizes (6.9", 6.5", 5.5" at minimum)
- [ ] App subtitle
- [ ] Keyword field
- [ ] Support URL

---

## Android Play Store Status: ❌ NOT READY

### Hard Blockers

| # | Issue | Severity | Status |
|---|-------|----------|--------|
| 1 | `applicationId = "com.example.trackora"` | CRITICAL | ❌ |
| 2 | Release build uses debug signing | CRITICAL | ❌ |
| 3 | `namespace = "com.example.trackora"` | CRITICAL | ❌ |

### Target SDK

`minSdk` and `targetSdk` use `flutter.minSdkVersion` / `flutter.targetSdkVersion` from the Flutter SDK defaults. Flutter 3.x defaults to minSdk 21, targetSdk 34. **✅ Acceptable for Play Store.**

### Android Permissions

`AndroidManifest.xml` not inspected directly but the declared Flutter packages imply:
- `INTERNET` — required for Firebase/Supabase ✅
- `USE_BIOMETRIC`, `USE_FINGERPRINT` — local_auth ✅
- `CAMERA` — image_picker ✅
- `READ_EXTERNAL_STORAGE` / `READ_MEDIA_IMAGES` — image_picker/file_picker ✅
- `VIBRATE` — home_widget ✅

Verify `READ_CONTACTS` is NOT in the manifest (app doesn't use contacts).
