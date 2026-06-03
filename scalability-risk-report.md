# Trackora — Scalability Risk Report

> Generated: 2026-05-16 | Branch: develop | Backend: Firebase Spark (free) + Supabase Free

---

## Free Tier Limits Reference

### Firebase Spark (Free)
| Resource | Limit | Notes |
|----------|-------|-------|
| Firestore reads | 50,000/day | ~1,000 active users = limit hit |
| Firestore writes | 20,000/day | |
| Firestore deletes | 20,000/day | |
| Storage | 1 GB | Migrated to Supabase — N/A |
| Auth users | Unlimited | ✅ |
| Hosting | 10 GB/month | Not used |

### Supabase Free
| Resource | Limit | Notes |
|----------|-------|-------|
| Storage | 1 GB | Can fill quickly with uncompressed receipts |
| Bandwidth | 5 GB/month | Public bucket = every image view = egress |
| Database | 500 MB | Not used for app data |

---

## RISK-1: Unbounded Real-Time Listeners on All Collections

**Severity:** HIGH  
**Files:** All `firebase_*_repository.dart` files

Every major collection uses `.snapshots()` with no `.limit()`:

```dart
// firebase_expense_repository.dart:20
return _expensesRef(userId).snapshots()
// firebase_account_repository.dart:19
return _accountsRef(userId).snapshots()
// firebase_installment_repository.dart:20
return _installmentsRef(userId).snapshots()
// firebase_borrow_lending_repository.dart:24
return _ref(userId).snapshots()
// firebase_saving_plan_repository.dart:20
return _ref(userId).snapshots()
```

**Risk:** A power user with 5,000 expenses triggers one read per document on every app open. That's 5,000 Firestore reads per session, multiplied by all active users.

**Cost math:** At 500 users × 500 expenses × 2 opens/day = **500,000 reads/day** — 10× over the free limit, and on Blaze plan: `500,000 × $0.036/100k = $0.18/day` ($65/month). Grows linearly with users.

**Fix for MVP:** Add date range filter to expense listener (load only last 3 months by default):
```dart
final cutoff = DateTime.now().subtract(const Duration(days: 90));
return _expensesRef(userId)
    .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
    .snapshots();
```

**Fix for scale:** Implement pagination — load 50 expenses at a time, fetch more on scroll.

---

## RISK-2: No Firebase Usage Quotas / Budget Alerts

**Severity:** HIGH  

There are no Firebase budget alerts configured. On the Spark plan you can't get billed, but when you upgrade to Blaze (required for any production scaling), unexpected traffic can generate unbounded costs.

**Fix:** Immediately after upgrading to Blaze:
1. Firebase Console → Billing → Set Budget Alert at $5, $25, $100
2. Enable Firebase App Check to block non-app API calls
3. Monitor the Firestore Usage tab daily for the first month

---

## RISK-3: Supabase Receipt Images — No Size Limit or Dimension Cap

**Severity:** HIGH  
**File:** `lib/screens/expenses/add_edit_expense_screen.dart:305`

Images are compressed to `imageQuality: 70` and `85` before upload, but there is no maximum dimension or file size enforcement. A 12MP photo at quality 70 can still be 2–4 MB.

**Risk:** 
- 1 GB Supabase storage limit fills at ~250–500 receipts for one user
- 5 GB bandwidth = ~1,250–2,500 image views/month total (public bucket, every load = egress)
- Multiple users exhaust both limits in weeks

**Fix:**
```dart
// Before upload, resize to max 1200px on longest side:
import 'package:image/image.dart' as img;

Future<File> _resizeImage(File file) async {
  final bytes = await file.readAsBytes();
  var image = img.decodeImage(bytes)!;
  if (image.width > 1200 || image.height > 1200) {
    image = img.copyResize(image, width: image.width > image.height ? 1200 : -1, height: image.height >= image.width ? 1200 : -1);
  }
  final resized = File('${file.parent.path}/resized_${file.uri.pathSegments.last}');
  await resized.writeAsBytes(img.encodeJpg(image, quality: 75));
  return resized;
}
```

Also add a file size check before upload (reject > 5MB with user error message).

---

## RISK-4: Supabase Public Bucket Bandwidth

**Severity:** MEDIUM  
**File:** `lib/services/storage_service.dart:60`

Using `getPublicUrl()` means every image load goes through Supabase CDN bandwidth. On Supabase free tier, 5 GB/month bandwidth is shared across all users.

**Risk:** At ~500KB average receipt size, 5 GB = ~10,000 image views/month total. A single active user viewing receipts daily could exhaust this for everyone.

**Fix:** 
1. Short term: Add `cached_network_image` caching so images are fetched once and cached on device
2. Medium term: Switch to signed URLs with private bucket (prevents hotlinking too)
3. Long term: Consider Cloudflare R2 (free egress) for receipt storage

---

## RISK-5: No Compound Firestore Indexes Documented

**Severity:** MEDIUM  

The expense repository uses compound queries:
```dart
// firebase_expense_repository.dart:32-33
.where('date', isGreaterThanOrEqualTo: ...)
.where('date', isLessThan: ...)
```

Single-field range queries on `date` don't need composite indexes, but if you add category filters combined with date ranges in the future, you'll get Firestore `FAILED_PRECONDITION` errors in production.

**Fix:** Create a `firestore.indexes.json` file and document any needed composite indexes now. Run `firebase firestore:indexes` to export current index configuration.

---

## RISK-6: Real-Time Listener Costs for Travel Groups (Cross-User)

**Severity:** MEDIUM  
**File:** `lib/repositories/firebase_travel_group_repository.dart:99,142`

Travel group expenses and members use `.snapshots()` (real-time). Every change by any group member triggers a read for all group members. For a travel group with 10 people making 50 expenses, that's 500 reads just for the expense stream setup, plus live updates.

**Fix:** For travel expenses specifically, switch to one-time `.get()` fetches with manual refresh (pull-to-refresh) instead of live snapshots. Travel expenses don't need millisecond-level real-time updates.

---

## Free Tier Runway Estimate

| Scenario | Firebase Reads/Day | Days Until Limit |
|----------|--------------------|-----------------|
| 10 DAU, 100 expenses avg | ~50k | At limit daily |
| 50 DAU, 100 expenses avg | ~250k | Over limit by 5× |
| 100 DAU, 200 expenses avg | ~1M | Over limit by 20× |

**Recommendation:** Add date-range filtering to expense queries before launch. This extends free tier runway by 3–6×. Plan to upgrade to Firebase Blaze (pay-as-you-go) once you exceed 20–30 daily active users.
