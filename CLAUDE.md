# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Project Rules

- Do NOT create worktrees or claude/* branches. Always work directly on the current branch.
- If unsure which branch to use, ask — do not create a new one.
- Do not create new branches or worktrees.
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
`main()` → `TrackoraBootstrap` (init Firebase + Supabase + LocalStorage) → `TrackoraApp` (Riverpod + theme + locale) → auth gate → `HomeShell` (4-tab shell: Dashboard / Statistics / Budget / Assets).

### Repository pattern
Every domain entity has three files:
- `lib/repositories/<entity>_repository.dart` — abstract interface
- `lib/repositories/firebase_<entity>_repository.dart` — Firestore implementation
- `lib/repositories/local_<entity>_repository.dart` — Hive implementation

Riverpod providers in `lib/state/providers.dart` select the correct implementation based on `storageMode` and the signed-in user.

### Local storage (Hive)
`lib/repositories/local_storage.dart` holds all box names and must be `init()`-ed at startup. New boxes must be added there and opened in `LocalStorage.init()`.

### Services layer
`lib/services/` contains stateless helpers consumed by screens and providers:
- `sync_service.dart` — offline→online Hive→Firestore migration on sign-in
- `expense_service.dart`, `installment_service.dart`, etc. — domain logic
- `i18n.dart` — `AppStrings` + `context.t('key')` extension; strings are in `_en`, `_zh`, `_ms` maps; missing translations fall through to English
- `money_format.dart` — formatting; `currency_converter.dart` / `exchange_rate_service.dart` — FX
- `ocr_parser.dart` — receipt OCR; `storage_service.dart` — Supabase image upload

### Theme
`lib/theme/app_theme.dart`:
- `AppTheme.light()` / `AppTheme.dark()` produce the `ThemeData`
- `BrandColors` is a `ThemeExtension` — access via `context.brand` (e.g. `context.brand.surface`, `context.brand.ink`)
- `AppColors` has static constants (`AppColors.income`, `AppColors.expense`, `AppColors.background`)
- `AppRadius.card` = standard card corner radius

### Shared widgets
- `AppToast.show(context, message, type: AppToastType.success)` — animated frosted-glass toast for all user feedback
- `SectionCard` — standard rounded surface card; automatically applies `OnPastel` for dark-text on light pastel backgrounds
- `PillTabs`, `MonthFilterBar`, `CurrencyPicker`, `PersonAvatar` — reusable UI in `lib/widgets/`

## Animation & UI Interaction Standards

- Every user action must have a response animation or UI interaction.
- Button press: scale down slightly (0.96) with a bounce-back on release.
- Success actions (save, update, delete): show a clear success indicator — checkmark animation, snackbar, or modal — consistent with existing patterns.
- Screen transitions: use smooth slide or fade, never hard cuts.
- Tab/toggle switches: animate the pill/thumb and fade in/out any fields that appear or disappear (duration ~250ms, ease curve).
- Icon state changes (e.g. toggles): use AnimatedSwitcher or TweenAnimationBuilder — smooth color + scale transition, never abrupt.
- List changes (add, delete, reorder): animate the item in/out, never snap. Use AnimatedList or implicit animations.
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
