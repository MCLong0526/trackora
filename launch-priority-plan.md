# Trackora — Launch Priority Plan

> Generated: 2026-05-16 | Branch: develop

---

## FINAL VERDICT

> ### ❌ Not Ready for Deployment
>
> The app has a solid foundation — authentication is strong, Firestore rules are mostly correct, the UI is clean, and both Sign In with Apple and Google Sign-In are properly implemented. However, **3 hard blockers** prevent App Store submission today, and **2 critical operational gaps** (no crash reporting, no analytics) mean you'd be flying blind after launch.
>
> **Estimated effort to reach "Deployable":** 3–5 focused days.

---

## Sprint Plan: Launch in 5 Days

### Day 1 — Unblock App Store Submission

**Goal:** Remove all submission blockers.

1. **Create `PrivacyInfo.xcprivacy`** (`ios/Runner/`)
   - Add required reason APIs: UserDefaults (CA92.1), FileTimestamp (C617.1), DiskSpace (85F4.1)
   - Add to Xcode Runner target
   - Time: 1 hour

2. **Fix Android `applicationId`** (`android/app/build.gradle.kts`)
   - Change `com.example.trackora` → `com.michaelchia.trackora`
   - Change `namespace` → `com.michaelchia.trackora`
   - Update `android/app/google-services.json` to match (re-run `flutterfire configure`)
   - Time: 30 minutes

3. **Configure Android release signing**
   - Generate release keystore, store securely outside repo
   - Update `build.gradle.kts` with proper signing config
   - Time: 1 hour

4. **Gitignore Firebase config files**
   - Add to `.gitignore`: `lib/firebase_options.dart`, `ios/Runner/GoogleService-Info.plist`, `android/app/google-services.json`
   - Document regeneration steps in `README.md`
   - Time: 30 minutes

---

### Day 2 — Add Crash Reporting + Analytics

**Goal:** Production observability before first user.

5. **Add Firebase Crashlytics**
   ```yaml
   firebase_crashlytics: ^4.1.0
   ```
   Wire up `FlutterError.onError` and `PlatformDispatcher.instance.onError` in `main.dart`.
   Time: 2 hours

6. **Add Firebase Analytics**
   ```yaml
   firebase_analytics: ^11.3.0
   ```
   Log key events: `expense_added`, `account_created`, `travel_group_joined`.
   Time: 2 hours

---

### Day 3 — Security Tightening

**Goal:** Close the two Firestore rule gaps and the debug log leak.

7. **Tighten invite code Firestore rules** (`firestore.rules`)
   - Add `ownerId` ownership check to `travelInviteCodes` writes
   - Scope `travelEmailInvites` reads to inviter/invitee only
   - Time: 1 hour + test in emulator

8. **Restrict `members` collection reads** (`firestore.rules`)
   - Limit to group members / owner only
   - Time: 1 hour + test

9. **Remove production debug logs**
   - Gate all `dev.log()` / `print()` calls behind `kDebugMode` in 4 files:
     `storage_service.dart`, `sync_service.dart`, `add_edit_expense_screen.dart`, `import_receipt_screen.dart`
   - Time: 1 hour

---

### Day 4 — Scalability Quick Wins

**Goal:** Extend free tier runway to support first 100+ users.

10. **Add date-range filter to expense listener** (`firebase_expense_repository.dart`)
    - Default to last 90 days
    - Add "load earlier" option in UI
    - Time: 2–3 hours

11. **Add image size validation + max dimension cap** (upload screens)
    - Reject files > 5MB with a toast
    - Resize to max 1200px before upload using the `image` package (already in dev dependencies)
    - Time: 2–3 hours

12. **Add `cached_network_image`** for receipt display
    - Prevents re-downloading same receipt on every view
    - Reduces Supabase bandwidth by 80%+
    - Time: 1–2 hours

---

### Day 5 — App Store Polish & Submission Prep

**Goal:** Pass App Store review on first attempt.

13. **Add privacy policy** — create a simple web page and link it in:
    - App Store Connect listing
    - In-app settings screen
    - Time: 2 hours

14. **Verify Sign In with Apple appears in UI** — confirm the Apple button is visible on welcome/login screen

15. **Bump version**: `pubspec.yaml` → `version: 1.0.0+2` (or your intended launch version)

16. **Run flutter_launcher_icons** to regenerate all icon sizes: `dart run flutter_launcher_icons`

17. **Set up Firebase Budget Alert** — Firebase Console → Billing → Budget & Alerts → $10 threshold

18. **TestFlight beta** — invite 5–10 testers, collect feedback, fix any crashes surfaced by Crashlytics

19. **App Store submission** — submit for review

---

## Post-Launch Backlog (Week 2+)

| Priority | Task |
|----------|------|
| High | Switch Supabase receipts to signed URLs (private bucket) |
| High | Add pagination to expense list |
| High | Add email verification enforcement |
| Medium | Add Firebase App Check to prevent API abuse |
| Medium | Add composite Firestore indexes file |
| Medium | Implement pull-to-refresh on travel expenses (replace real-time listener) |
| Low | Add password reset flow (verify it exists) |
| Low | Landscape mode testing |
| Low | iPad layout verification |

---

## Risk Summary

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| App Store rejection (PrivacyInfo) | 100% if not fixed | Blocks launch | Day 1 fix |
| App Store rejection (Android ID) | 100% if not fixed | Blocks Play Store | Day 1 fix |
| Free tier quota exceeded at 50 DAU | High | Service disruption | Day 4 fix |
| Supabase storage exhausted at 300 receipts | Medium | Upload failures | Day 4 fix |
| Undetected crash causes user churn | High | Reputation damage | Day 2 fix |
| Invite code abuse | Low | Cost/privacy | Day 3 fix |
