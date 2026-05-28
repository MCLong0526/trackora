# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Project Rules

- Do NOT create worktrees or claude/* branches. Always work directly on the current branch.
- If unsure which branch to use, ask — do not create a new one.
- Do not change unrelated files or pages.
- Keep changes small and focused — one task at a time.
- Match existing code style and patterns.
- UI: clean, premium, modern, iOS-style. Follow DESIGN.md.
- If a Figma or Claude design link is provided, follow it strictly.
- Use screenshots as reference when provided.
- Run `git status` before and after every change.
- Run `dart analyze` after every change. Fix all warnings before finishing.

## Commands

```bash
flutter analyze          # lint — must pass with zero issues before finishing
flutter test             # run all tests
flutter test test/widget_test.dart   # run a single test file
flutter run              # run on connected device/emulator
flutter run -d chrome    # run on web
```

## Architecture

**Stack:** Flutter/Dart · Firebase (Auth + Firestore) · Supabase (receipt image storage) · Riverpod (state) · Hive (local/offline cache)

**Storage mode** is a compile-time flag in `lib/app_config.dart`:
```dart
const StorageMode storageMode = StorageMode.firebase;  // firebase | local
```
When `firebase`, the app uses Firestore + Firebase Auth and also writes a local Hive cache for offline fallback. When `local`, it runs fully offline with Hive only.

### Startup flow
`main()` → `TrackoraBootstrap` (init Firebase + Supabase + LocalStorage + WidgetSyncService) → `TrackoraApp` (Riverpod + theme + locale) → `_AuthGate` → `HomeShell` (4-tab shell: Dashboard / Statistics / Budget / Assets).

`TrackoraApp` is a `ConsumerStatefulWidget` with `WidgetsBindingObserver`. On foreground resume it drains the iOS widget/shortcut queue, handles share-extension deep links, syncs to Apple Watch, and restores Live Activity.

### Repository pattern
Every domain entity has three files:
- `lib/repositories/<entity>_repository.dart` — abstract interface
- `lib/repositories/firebase_<entity>_repository.dart` — Firestore implementation
- `lib/repositories/local_<entity>_repository.dart` — Hive implementation

Riverpod providers in `lib/state/providers.dart` select the correct implementation based on `storageMode` and the signed-in user.

**Entities:** expense, account, installment, person, borrow_lending, saving_plan, precious_metal, travel_group, stock_investment, expense_group (shared group expenses).

### Local storage (Hive)
`lib/repositories/local_storage.dart` holds all box names and must be `init()`-ed at startup. New boxes must be added there and opened in `LocalStorage.init()`.

The offline-first strategy in Firebase mode: `expensesProvider` falls back to `LocalExpenseRepository` when offline or while `pendingExpenseChangeCountProvider > 0`, avoiding flicker when new entries are created offline.

### Providers overview (`lib/state/providers.dart`)
Key providers to know:
- `authStateProvider` — `StreamProvider<AppUser?>` from `AuthService.authStateChanges`
- `expensesProvider` — current month's expenses; offline-aware
- `allExpensesProvider` — lifetime expenses (used for savings/net worth)
- `accountsProvider` — sorted by `_kAccountTypeOrder` then `createdAt`
- `totalAccountBalanceProvider` — sum of all account balances in user's base currency
- `homeModeProvider` — `HomeMode.personal | HomeMode.group`
- `activeGroupIdProvider` — selected expense group ID
- `themeModeProvider`, `localeProvider`, `balanceVisibleProvider` — persisted user prefs
- `homeCardOrderProvider`, `moneyHubOrderProvider` — draggable card order (persisted)
- `useCustomCycleProvider`, `cycleDayStartProvider` — custom expense cycle (not calendar month)
- `pendingExpenseChangeCountProvider` — count of offline entries pending Firestore sync
- `autoSyncProvider` — long-lived provider watched by `TrackoraApp`; triggers `SyncService` on offline→online transition

### Services layer (`lib/services/`)
Stateless helpers consumed by screens and providers:
- `sync_service.dart` — offline→online Hive→Firestore migration on sign-in
- `expense_service.dart`, `installment_service.dart`, `saving_plan_service.dart`, `borrow_lending_service.dart`, `person_service.dart` — domain logic
- `travel_group_service.dart`, `expense_group_service.dart` — group travel & shared expense logic
- `stock_service.dart` — stock investment helpers
- `i18n.dart` — `AppStrings` + `context.t('key')` extension; strings in `_en`, `_zh`, `_ms` maps; missing keys fall through to English
- `money_format.dart` — amount formatting; `currency_converter.dart` / `exchange_rate_service.dart` — FX; `fx_preferences_service.dart` — starred/hidden currencies (Firestore-synced)
- `ocr_parser.dart` — receipt OCR; `storage_service.dart` — Supabase image upload
- `prefs_service.dart` — SharedPreferences wrapper; holds `defaultHomeCards`, `defaultMoneyHubOrder`, `defaultStatsSections`
- `auth_service.dart` — Firebase Auth wrapper producing `AppUser?` stream
- `biometric_service.dart` — local_auth integration
- `deep_link_service.dart` — handles share-extension and App Shortcut deep links via `rootNavKey`
- `live_activity_service.dart` — iOS Live Activity (Dynamic Island / Lock Screen widget)
- `watch_service.dart` — Apple Watch connectivity via `watch_connectivity`; bridges "addExpense" messages from Watch
- `widget_sync_service.dart` / `widget_intent_service.dart` — iOS/Android home-screen widget data push and "quick add" intent drain

### Theme (`lib/theme/app_theme.dart`)
- `AppTheme.light()` / `AppTheme.dark()` produce `ThemeData`
- `BrandColors` is a `ThemeExtension` — access via `context.brand` (e.g. `context.brand.surface`, `context.brand.ink`, `context.brand.accentDark`, `context.brand.inkSoft`)
- `AppColors` has static constants (`AppColors.income`, `AppColors.expense`, `AppColors.background`)
- `AppActionBlue.color` — the primary action color (purple-blue) used in bottom nav and FAB
- `AppRadius.card` = standard card corner radius

### HomeShell (`lib/screens/home/home_shell.dart`)
4-tab shell with a center FAB speed-dial. The floating bottom nav bar supports drag-to-switch (swipe across tabs). Tab layout: Home | Stats | [FAB gap] | Budget | Assets. In `HomeMode.group` on the Dashboard tab the FAB becomes a direct "Group Add" button instead of opening the speed dial.

### Shared widgets (`lib/widgets/`)
- `AppToast.show(context, message, type: AppToastType.success)` — animated frosted-glass toast for all user feedback
- `SectionCard` — standard rounded surface card; automatically applies `OnPastel` for dark-text on light pastel backgrounds
- `PillTabs`, `MonthFilterBar`, `CurrencyPicker`, `PersonAvatar`, `MaskedAmount`, `PersonalGroupToggle` — reusable UI
- `AnimatedDonutChart` — chart widget used in statistics screens

### Domain model highlights
- `Expense.convertedAmount` / `Expense.baseCurrencyAmount` — use the frozen `baseCurrencyAmount` when available; fall back to live converter. `_effectiveAmount()` in providers picks the right value per account currency.
- `ExpenseGroup` — multi-user shared expense group (Firestore + Hive dual-write). `groupExpensesProvider` always reads from local Hive; `groupExpenseSyncProvider` syncs Firestore→Hive in background.
- `TravelGroup` — single-trip travel expense split with settlement calculations.
- `StockInvestment` — Firebase-only (no local repo).

## Animation & UI Interaction Standards

- Every user action must have a response animation or UI interaction.
- Button press: scale down slightly (0.96) with a bounce-back on release.
- Success actions (save, update, delete): show a clear success indicator — checkmark animation, snackbar, or modal — consistent with existing patterns.
- Screen transitions: use smooth slide or fade, never hard cuts.
- Tab/toggle switches: animate the pill/thumb and fade in/out any fields that appear or disappear (duration ~250ms, ease curve).
- Icon state changes (e.g. toggles): use `AnimatedSwitcher` or `TweenAnimationBuilder` — smooth color + scale transition, never abrupt.
- List changes (add, delete, reorder): animate the item in/out, never snap. Use `AnimatedList` or implicit animations.
- Loading states: always show a skeleton or spinner, never a blank screen.
- Empty states: always show a meaningful empty state UI, never blank.
- All animations: duration 200–350ms, use ease or easeInOut curves. Never use linear for UI animations.
- When in doubt: add the animation. Smooth > static, always.

## i18n

Add strings to `AppStrings._en` (required), then mirror in `_zh` and `_ms`. Look up in widgets via `context.t('key')`. The app supports English, Chinese (Simplified), and Malay; untranslated keys fall through to English automatically.

## Branches & Context

- `main` — production
- `latest_develop` — active development
- Use `/compact` when context becomes large; `/clear` after completing each independent task.
