# Trackora — Security Audit

> Generated: 2026-05-16 | Branch: develop

---

## Summary

| Category | Status |
|----------|--------|
| Authentication | ✅ Solid |
| Firestore Rules | ⚠️ Two gaps |
| Firebase Storage Rules | ✅ Good |
| Supabase Storage | ⚠️ Public bucket |
| Secrets Management | ❌ Keys in git |
| Network Security | ✅ HTTPS everywhere |
| Client-side Security | ⚠️ Debug logs in prod |

---

## SEC-1: Firebase API Keys Committed to Repository

**Severity:** HIGH  
**Files:** `lib/firebase_options.dart`, `ios/Runner/GoogleService-Info.plist`, `android/app/google-services.json`

Firebase client keys are committed to git and not listed in `.gitignore`. The `supabase_config.dart` file is correctly gitignored — this pattern should be applied to Firebase config too.

**Risk:** If the repository is public (or becomes public via a settings change), your Firebase project ID and API key are indexed by GitHub search. While Firestore security rules protect data access, the API key can be used to:
- Exhaust your Firebase free-tier quota (50k reads/day, 20k writes/day)
- Trigger auth sign-up floods (creating fake accounts)
- Send data to your project that triggers cost

**Fix:**
```
# .gitignore
lib/firebase_options.dart
ios/Runner/GoogleService-Info.plist
android/app/google-services.json
```

Use `flutterfire configure` in CI with service account credentials to regenerate.

---

## SEC-2: Firestore — Invite Collections Overly Permissive

**Severity:** HIGH  
**File:** `firestore.rules:54-64`

```javascript
match /travelInviteCodes/{code} {
    allow read: if isAuth();   // ← any auth user can enumerate ALL codes
    allow write: if isAuth();  // ← any auth user can create/overwrite ANY code
}

match /travelEmailInvites/{docId} {
    allow read, write: if isAuth();  // ← same problem
}
```

**Risk:**
- Any signed-in user can enumerate all invite codes (privacy leak — reveals which groups exist)
- Any signed-in user can overwrite someone else's invite code, breaking their join flow
- A malicious user can flood the collection with fake invite codes (DoS / cost attack)

**Fix:**
```javascript
match /travelInviteCodes/{code} {
    // Anyone can read a specific code to attempt a join
    allow read: if isAuth();
    // Only the code creator (owner of the referenced group) can write
    allow create: if isAuth() && request.resource.data.ownerId == request.auth.uid;
    allow update, delete: if isAuth() && resource.data.ownerId == request.auth.uid;
}

match /travelEmailInvites/{docId} {
    // Only the invitee (by email) or inviter can read
    allow read: if isAuth() && (
        resource.data.invitedEmail == request.auth.token.email ||
        resource.data.inviterUid == request.auth.uid
    );
    allow create: if isAuth() && request.resource.data.inviterUid == request.auth.uid;
    allow delete: if isAuth() && resource.data.inviterUid == request.auth.uid;
}
```

---

## SEC-3: Firestore — Travel Group Members Readable by Any Authenticated User

**Severity:** MEDIUM  
**File:** `firestore.rules:38-48`

```javascript
match /users/{ownerId}/travelGroups/{groupId}/members/{docId} {
    allow read: if isAuth();  // ← any auth user, not just group members
```

The comment says this is "needed for duplicate-member check on join" but that check can be done more narrowly.

**Risk:** Any signed-in user who knows (or guesses) a `ownerId` + `groupId` can read the full members list of any travel group, exposing usernames and user IDs of all members.

**Fix:**
```javascript
match /users/{ownerId}/travelGroups/{groupId}/members/{docId} {
    // Group members, owner, or self-lookup only
    allow read: if isAuth() && (
        request.auth.uid == ownerId ||
        request.auth.uid in
            get(/databases/$(database)/documents/users/$(ownerId)/travelGroups/$(groupId))
                .data.memberIds ||
        resource.data.userId == request.auth.uid
    );
    allow write: if isAuth() && (
        request.auth.uid == ownerId ||
        request.auth.uid in
            get(/databases/$(database)/documents/users/$(ownerId)/travelGroups/$(groupId))
                .data.memberIds ||
        request.resource.data.userId == request.auth.uid
    );
}
```

---

## SEC-4: Supabase Storage — Public Bucket, No RLS

**Severity:** MEDIUM  
**File:** `lib/services/storage_service.dart:60`

```dart
final publicUrl = supabase.storage.from(supabaseBucket).getPublicUrl(path);
```

Receipts are stored in a **public** Supabase bucket (uses `getPublicUrl`). This means:
- Anyone with the URL can view any receipt image
- URLs follow a predictable pattern: `{supabaseUrl}/storage/v1/object/public/receipts/{userId}/{timestamp}.jpg`

**Risk:** Receipt images contain sensitive financial information. If the bucket name and URL pattern are discovered, an attacker could enumerate receipts by guessing timestamps for a known user ID. Firebase UIDs are not secret (they appear in Firestore paths).

**Fix (preferred):** Switch to a private bucket with signed URLs:
```dart
// Generate a signed URL valid for 1 hour
final signedUrl = await supabase.storage
    .from(supabaseBucket)
    .createSignedUrl(path, 3600);
```

Store the path (not the URL) in Firestore and generate signed URLs on-demand when displaying receipts.

**Fix (acceptable for MVP):** Keep public bucket but add Supabase RLS policy restricting read to the path prefix matching the user's UID (requires Supabase Auth integration).

---

## SEC-5: Production Debug Logs

**Severity:** MEDIUM  
**Files:** `storage_service.dart`, `sync_service.dart`, `add_edit_expense_screen.dart`, `import_receipt_screen.dart`

24 `dev.log()` and `print()` calls remain active in production builds. These write to the device system log, which can be captured by:
- Connected Mac via Console.app or `idevicesyslog`
- Crash logs (if attached to error context)
- Developer tools on jailbroken devices

Logged data includes Supabase upload paths, receipt URLs, expense IDs, and sync state.

**Fix:**
```dart
// Replace all dev.log() calls with:
if (kDebugMode) {
  dev.log('[RECEIPT_UPLOAD] ...', name: 'StorageService');
}
```

Or use a proper logging package like `logger` with level filtering.

---

## SEC-6: No Email Verification Enforcement

**Severity:** LOW  
**File:** `lib/services/auth_service.dart`

Users can create accounts with any email address and immediately access all app features without verifying the email. There is a `verifyBeforeUpdateEmail()` call for email *changes*, but no verification on initial signup.

**Risk:** Fake account creation; users can impersonate email addresses in travel group invites (the invite system matches by email).

**Fix:** After `signUp()`, call `user.sendEmailVerification()`. Gate group-invite acceptance behind `user.emailVerified == true`.

---

## SEC-7: `biometric_service.dart` Storage Key

**Severity:** INFO (not a vulnerability)  
**File:** `lib/services/biometric_service.dart:9`

```dart
static const _kSecurePassword = 'trackora_secure_password';
```

This is a **storage key name** used with `flutter_secure_storage` (iOS Keychain), not an actual password. The actual credential is stored securely in Keychain. This is fine.

---

## Authentication Strength Assessment

| Feature | Status | Notes |
|---------|--------|-------|
| Email/password login | ✅ | Firebase Auth |
| Google Sign-In | ✅ | Proper OAuth flow |
| Sign In with Apple | ✅ | Required for App Store |
| Re-authentication for sensitive ops | ✅ | `changeEmail` requires current password |
| Sign-out clears Google session | ✅ | `GoogleSignIn().signOut()` called |
| No hardcoded credentials | ✅ | |
| Email verification | ❌ | Not enforced at signup |
| Password reset | Not checked | Verify it exists in UI |
| Session management | ✅ | Firebase handles persistence |
