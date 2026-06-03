# Trackora — Critical Issues

> Generated: 2026-05-16 | Branch: develop

---

## CRITICAL-1: Missing `PrivacyInfo.xcprivacy` (iOS App Store Blocker)

**Severity:** CRITICAL  
**File:** `ios/Runner/` (file does not exist)

**Problem:** Apple has required a privacy manifest (`PrivacyInfo.xcprivacy`) for all new and updated apps since Spring 2024. The file must declare which "required reason" APIs the app uses and why. The app uses `UserDefaults` (SharedPreferences), file timestamps, and the disk space API — all of which require declared reasons.

**Why it matters:** App Store Connect will hard-reject the build at upload time. No manual review, instant rejection.

**Fix:**
Create `ios/Runner/PrivacyInfo.xcprivacy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array>
        <string>CA92.1</string>
      </array>
    </dict>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array>
        <string>C617.1</string>
      </array>
    </dict>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryDiskSpace</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array>
        <string>85F4.1</string>
      </array>
    </dict>
  </array>
  <key>NSPrivacyCollectedDataTypes</key>
  <array/>
  <key>NSPrivacyTracking</key>
  <false/>
</dict>
</plist>
```

Then in Xcode: File → Add Files → select `PrivacyInfo.xcprivacy` → ensure "Target Membership: Runner" is checked.

---

## CRITICAL-2: Android `applicationId` is `com.example.trackora`

**Severity:** CRITICAL  
**File:** `android/app/build.gradle.kts:9,20`

**Problem:** The Android `applicationId` (the unique Play Store identifier) is left as `com.example.trackora`. This is the default placeholder with a `TODO` comment. The iOS bundle ID is `com.michaelchia.trackora`, meaning Android and iOS would register as completely different apps. No update path is possible after first publish with the wrong ID.

**Why it matters:** Google Play will reject or accept this as a permanent `com.example.*` ID which you cannot change later. It also mismatches the `google-services.json` Firebase config.

**Fix:**
```kotlin
// android/app/build.gradle.kts
defaultConfig {
    applicationId = "com.michaelchia.trackora"  // ← change this
    ...
}
namespace = "com.michaelchia.trackora"  // ← and this
```

---

## CRITICAL-3: Android Release Build Uses Debug Signing Keys

**Severity:** CRITICAL  
**File:** `android/app/build.gradle.kts:30-33`

**Problem:** The release build type explicitly signs with debug keys:
```kotlin
release {
    // TODO: Add your own signing config for the release build.
    signingConfig = signingConfigs.getByName("debug")
}
```

**Why it matters:** Google Play requires a proper release keystore. The debug key cannot be used for Play Store submissions. Also, once you publish with one key, you cannot change it — so get this right before first upload.

**Fix:**
1. Generate a release keystore: `keytool -genkey -v -keystore trackora-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias trackora`
2. Store it safely (NOT in the repo)
3. Reference it via environment variables or a local `key.properties` file (gitignored)
4. Configure in `build.gradle.kts`:
```kotlin
signingConfigs {
    create("release") {
        storeFile = file(System.getenv("KEY_STORE_PATH") ?: "../trackora-release.jks")
        storePassword = System.getenv("KEY_STORE_PASSWORD")
        keyAlias = System.getenv("KEY_ALIAS")
        keyPassword = System.getenv("KEY_PASSWORD")
    }
}
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
    }
}
```

---

## CRITICAL-4: Firebase API Keys Committed to Git

**Severity:** CRITICAL  
**Files:** `lib/firebase_options.dart`, `ios/Runner/GoogleService-Info.plist`, `android/app/google-services.json`

**Problem:** All three Firebase configuration files containing API keys, app IDs, and project IDs are committed to the repository with no `.gitignore` entry. While Firebase client-side keys are somewhat public by design, if the repo is or becomes public:
- Anyone can trigger writes to your Firestore via REST API  
- Your Firebase project ID and configuration is permanently leaked in git history  
- API quotas can be exhausted by abuse

**Why it matters:** Firebase API key abuse can cause unexpected billing. If repo is pushed to GitHub it becomes permanently public via git history even if you delete the files.

**Fix:**
```bash
# .gitignore — add these lines:
lib/firebase_options.dart
ios/Runner/GoogleService-Info.plist
android/app/google-services.json
```

Then add CI/CD steps to regenerate these files from `flutterfire configure` using service account credentials. Keep the repo private until this is resolved.

---

## CRITICAL-5: iOS Bundle ID Mismatch in `firebase_options.dart`

**Severity:** CRITICAL  
**File:** `lib/firebase_options.dart:66`

```dart
iosBundleId: 'com.example.trackora',  // ← wrong
```

The actual iOS bundle ID in `project.pbxproj` is `com.michaelchia.trackora`. This mismatch causes Firebase to fail initialization on iOS production builds — Auth, Firestore, and all Firebase services will break.

**Fix:**
```dart
iosBundleId: 'com.michaelchia.trackora',
```

Or re-run `flutterfire configure` with the correct bundle ID to regenerate `firebase_options.dart`.

---

## CRITICAL-6: iOS Extension `IPHONEOS_DEPLOYMENT_TARGET = 26.2` (Invalid Version)

**Severity:** CRITICAL  
**File:** `ios/Runner.xcodeproj/project.pbxproj:1394,1437,1477`

Three build configurations for an iOS extension target have `IPHONEOS_DEPLOYMENT_TARGET = 26.2`. iOS 26.2 does not exist. This is almost certainly a typo for `16.2` or `16.0`. Xcode will either fail to build or App Store Connect will reject the binary as incompatible.

**Fix:** Open Xcode → select the extension target (ShareExtension or OcrExtension) → General → Deployment Info → set minimum iOS version to `16.0` or the correct value.

---

## CRITICAL-7: No Crash Reporting in Production

**Severity:** CRITICAL (operational)  
**File:** `lib/main.dart`, `pubspec.yaml`

**Problem:** There is no `firebase_crashlytics` or equivalent crash reporting integration. In production you will have zero visibility into crashes affecting real users.

**Why it matters:** You will be flying blind after launch. Users will churn due to crashes you never know about.

**Fix:**
```yaml
# pubspec.yaml
dependencies:
  firebase_crashlytics: ^4.1.0
  firebase_analytics: ^11.3.0
```

```dart
// main.dart, inside _start():
FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
PlatformDispatcher.instance.onError = (error, stack) {
  FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  return true;
};
await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
```
