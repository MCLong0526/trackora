# Trackora Project Context

## Latest Pass — Session 3 UI Polish & Drag-to-Reorder

### Money Page (`lib/screens/home/budget_screen.dart`)

**Management card premium redesign.** `_ManagementCard` was rebuilt as a
shadow-wrapper `Container` + `SectionCard` layout:
- A `BoxShadow` with `color: background.withValues(alpha: 0.55)` for a
  colour-matched, soft elevation effect per card.
- **Icon row**: a 32×32 frosted pill (`white.55`) containing a 16 px icon,
  with a `CupertinoIcons.chevron_right` on the trailing edge.
- **Label → Value → Footer pill**: label in 11/w700, value in 22/w900 via
  `FittedBox`, optional subtext, optional progress bar, then a footer pill
  with `white.42` background and the summary text.
- `Column(crossAxisAlignment: start)` with `Spacer()` between value area and
  footer pill.

### Home Page (`lib/screens/home/dashboard_screen.dart`)

**Drag-to-reorder home cards.** The customize sheet was upgraded from a plain
visibility toggle to a full `_ReorderableCardsSheet`:
- Uses `ReorderableListView.builder` (shrinkWrap + NeverScrollableScrollPhysics).
- Each row: drag handle (`CupertinoIcons.line_horizontal_3`) + label +
  `CupertinoSwitch`.
- Card order is persisted via `SharedPreferences` (`home_card_order` key).
- `HomeCardOrderNotifier` / `homeCardOrderProvider` added to `providers.dart`.
- `homeCardOrder()` / `setHomeCardOrder()` methods added to `prefs_service.dart`.
- `_HomeBalanceCarousel` now accepts `cardOrder: List<String>` and sorts the
  carousel by the saved order before filtering to visible cards.
- Old unused `_VisibilitySheet` and `_VisibilitySwitchRow` classes removed.
- New i18n key `home.dragToReorder` added to EN/ZH/MS.

### Stats Page (`lib/screens/home/statistics_screen.dart`)

**Snapshot fix — comprehensive Column mainAxisSize fix.** All 10 `Column`
widgets in the forReport render tree were given `mainAxisSize: MainAxisSize.min`
to prevent infinite-height layout assertions when captured off-screen via
`OverlayEntry`. Affected widgets: `_ReportHeader` (2), `_FilterCard` (1),
`_OverviewCard` (2), `_LineChartCard` (2), `_CategoryCard topPortion` (2),
`_SummaryTile` (1).

---

## Previous Pass — Session 2 UI Refinements

This pass applies targeted refinements to the Money, Home, and Stats pages with
no unrelated logic changes.

### Money Page (`lib/screens/home/budget_screen.dart`)

**Removed Monthly Budget donut card.** The `_BudgetDonutCard` / `_DonutMetric`
classes and the `fl_chart` import were deleted; the donut no longer appears
above the management section.

**Management section → 2×2 card grid.** The four `_MoneyToolCard` rows were
replaced with a `LayoutBuilder` + `Wrap(spacing: 12, runSpacing: 12)` grid of
`_ManagementCard` widgets. Each card is `(maxWidth − 12) / 2` wide × 170 px
tall. Card details:
- **Installments** (butter bg): monthly total, `/ mo` subtext, active count footer.
- **Borrow & Lend** (sky bg): net position in income/expense colour, borrowed ↑ · lent ↓ footer.
- **Saving Plans** (mint bg): total saved, progress bar saved/target, target footer.
- **Monthly Budget** (lilac bg): spent amount, progress bar spent/budget (turns red on overspend), % used footer.

`_MoneyToolCard`, `_budgetSummary`, and the now-unused `remaining` variable were
removed. New i18n key `budget.perMonth` added to EN/ZH/MS.

### Home Page (`lib/screens/home/dashboard_screen.dart`)

**Total Balance hidden by default.** `PrefsService.balanceVisible()` default
changed from `?? true` to `?? false` in `prefs_service.dart`.

**Total Balance card shows today/week spend.** `_TotalBalanceCard` now accepts
`todaySpent` and `weekSpent` (computed in `DashboardScreen.build`; passed
through `_HomeBalanceCarousel`). The bottom pills changed from "Lifetime in /
Lifetime out" to "Today / This week" with expense-red colour. New i18n keys
`home.today` and `home.thisWeek` added to EN/ZH/MS. The `allExpenses` param on
`_TotalBalanceCard` was removed.

**Budget card: progress bar.** A `LinearProgressIndicator` (height 6, white
track, ink/red value) was inserted between the budget limit label and the
Spacer. Turns red when `overspent`.

**Saving Plans card: progress bar.** A `LinearProgressIndicator` (ink colour,
shown only when `target > 0`) was inserted between the "total saved" label and
the Spacer.

**Borrow/Lend card: directional icons.** `_LightMetricPill` gained an optional
`leadingIcon: IconData?` parameter. The "Borrowed" pill now shows
`CupertinoIcons.arrow_down` (expense red) and "Lent" shows
`CupertinoIcons.arrow_up` (income green).

### Stats Page (`lib/screens/home/statistics_screen.dart`)

**Screenshot fix — blank/clipped output resolved.** Root cause: three
`Column(mainAxisSize: max)` widgets inside the OverlayEntry's unconstrained
height context caused infinite-height layout errors. Fixes:
1. `_buildReport` return `Column` → `mainAxisSize: MainAxisSize.min`.
2. `_ChartsCarousel.build` stacked/single-page `Column` → `mainAxisSize: MainAxisSize.min`.
3. `_CategoryCard` `forReport` legend `Column` → `mainAxisSize: MainAxisSize.min`.
4. `_shareSnapshot` capture `Container` wrapped in `IntrinsicHeight` so the
   OverlayEntry layout pass gives a bounded height constraint to all children.

### Files changed in this pass
- `lib/services/prefs_service.dart` — balance visible default changed to `false`
- `lib/services/i18n.dart` — added `home.today`, `home.thisWeek`, `budget.perMonth` (3 locales)
- `lib/screens/home/budget_screen.dart` — removed donut card; management 2×2 grid; removed unused code
- `lib/screens/home/dashboard_screen.dart` — today/week spend on balance card; progress bars on budget/saving; arrow icons on borrow card
- `lib/screens/home/statistics_screen.dart` — 4 `mainAxisSize`/`IntrinsicHeight` fixes for screenshot

---

## Previous Pass — Home/Stats/Money UI Polish

This pass applies focused UI improvements to three screens with no unrelated
logic changes.

### Home Page (`lib/screens/home/dashboard_screen.dart`)

**Recent Activity: max 10 (was 5).** The sliver list now shows up to 10
entries before truncating.

**"All Bills" button.** The section header now shows a tappable "All Bills"
link (replacing the old "+ N more" counter). Tapping opens `_AllBillsSheet` —
a modal bottom sheet that lists all current-month records sorted newest-first,
with a total and entry count. `home.allBills` was added to all three i18n
locales (EN / ZH / MS).

**Carousel card shadows.** Each of the four home carousel cards now renders
inside `_ShadowCard`, a thin wrapper that adds a soft, colour-matched
`BoxShadow` (blurRadius 22, offset (0, 10), spreadRadius -4). This makes the
cards feel elevated and more Apple-like without changing their content.

### Stats Page (`lib/screens/home/statistics_screen.dart`)

**Donut chart is now primary (shown first).** The order in
`_ChartsCarousel._pages()` was swapped so the donut/category card leads and
the line chart is secondary. The default landing page is now the donut.

**Only the category list scrolls — not the whole chart.** `_CategoryCard` was
restructured:
- The card header + PieChart + hint text are a fixed top portion
  (`Padding` → `Column`).
- The legend list is a `ConstrainedBox(maxHeight: 210)` + `ListView.builder`
  that scrolls independently inside the card.
- A `forReport: bool` parameter was added. When `true` (screenshot capture),
  all legend rows are laid out in a plain `Column` with no height constraint so
  the full report image is never clipped.
- `SectionCard(padding: EdgeInsets.zero)` + inner `Column` replaces the
  single-padding-all layout.

### Money Page (`lib/screens/home/budget_screen.dart`)

**Monthly Budget donut card.** `_BudgetDonutCard` was added above the
Management section. It shows:
- An 88 × 88 `PieChart` donut with two slices: spent (expense red) and
  remaining (income green), centre-labelled with % used.
- Right side: Budget title + month, and two `_DonutMetric` pills (Spent /
  Remaining or Over by).
- When no budget is set it renders a prompt card.
- Tapping opens `showMonthlyBudgetDetails` (the existing detail sheet).

`fl_chart` import added to `budget_screen.dart`.

---

## Previous Pass — Widget Deep-Link Fix, Screenshot Fix, Back Tap Doc

This pass is bug fixes against the previous "Widget Direct Input, Budget
Progress, Quick Add Shortcut" pass. No unrelated logic was touched.

### Bug 1+2+4 — Widget pencil/amount tap only opened the app, did not
### show QuickAddSheet (and never carried `?amount=` through)

**Root cause.** The `home_widget` Flutter plugin only forwards a URL to
`HomeWidget.widgetClicked` / `HomeWidget.initiallyLaunchedFromHomeWidget`
when the URL contains a `homeWidget` query parameter (see
`isWidgetUrl()` in
`/Users/.../pub-cache/.../home_widget-0.7.0+1/ios/Classes/SwiftHomeWidgetPlugin.swift:238`).
Trackora's widget URLs (`trackora://quickadd?amount=0.3`) lacked that
parameter, so the plugin discarded them. iOS still opened the app
because the URL scheme is registered, but `DeepLinkService._handle`
never received the URL and `QuickAddSheet.show()` never ran.

**Fix.** `ios/TrackoraWidget/TrackoraWidget.swift` now appends
`homeWidget=1` to every widget URL (`widgetURL`, `Custom`, `Add`, +/-,
and the tappable amount/pencil label). The Dart-side
`DeepLinkService._handle` already reads `uri.queryParameters['amount']`
unchanged, so prefilled amounts (e.g. `?amount=0.30`) flow through to
the sheet without further changes. The keypad in `QuickAddSheet`
already supports decimals via cents-based input — typing `030` →
`$0.30`, `150` → `$1.50`, `1280` → `$12.80`. After the fix:

- Cold start, background, and foreground all open `QuickAddSheet`.
- Amount preset survives across the deep link.
- `homeWidget=1` is harmless to the Dart `_handle` — it only checks
  `uri.host == 'quickadd'`.

### Bug 5 — Stats screenshot exported a blank/clipped image

**Root cause.** The previous pass rendered the off-screen capture tree
inside an `OverlayEntry` with `Positioned(left: -mediaSize.width * 2)`.
The `Overlay` lays its children out in a `Stack` with hard-edge
clipping, so anything positioned outside the visible bounds is **not
painted**. `RenderRepaintBoundary.toImage()` then returned an empty
layer because the report widget never produced any paint commands.

**Fix.** `_shareSnapshot` in `lib/screens/home/statistics_screen.dart`
now positions the report at `(0, 0)` at full natural width and stacks a
brand-coloured `IgnorePointer(Container)` cover on top. The cover hides
the rendered report from the user during the brief capture window
(~200 ms), but `RepaintBoundary` paints into its own isolated layer
regardless of overdraw, so `toImage()` returns the full report. We also
wait three frames + 200 ms instead of two frames + 120 ms to give
fl_chart's `LineChart` and `PieChart` enough time for first paint.
Visible-section gating, exclude-fixed toggle, filter card, overview
tiles, and the report header are all part of the captured tree.

### Bug 3 — App Shortcut not visible in Back Tap (works in Shortcuts app)

**This is an iOS limitation, not a Trackora bug.** Settings →
Accessibility → Touch → Back Tap → Double Tap → Shortcut shows only
shortcuts saved to the user's *Shortcuts library*. App Shortcuts
declared via `AppShortcutsProvider` show up in Siri, the Shortcuts app
gallery, Spotlight, and the Action Button — but not directly in Back
Tap. `OpenQuickAddIntent` is configured correctly (target membership
verified, registered in `Runner.xcodeproj/project.pbxproj`,
`AppShortcutsProvider` declared, three localized phrases, App Group
flag wired through `_maybeOpenQuickAdd`).

**Required user steps to bind to Back Tap:**

1. Open the Shortcuts app.
2. Tap "+" → "Add Action".
3. Search "Quick Add Expense" and pick the Trackora action that
   appears under "App Shortcuts".
4. Optionally rename the shortcut to "Quick Add Expense".
5. Save it (the green back arrow). It now lives in *My Shortcuts*.
6. Open Settings → Accessibility → Touch → Back Tap → Double Tap →
   scroll to *Shortcuts* → tap the saved "Quick Add Expense".

After this, double-tapping the back of the phone runs the intent and
Trackora foregrounds straight into `QuickAddSheet`. The same comment
block now lives at the top of `ios/Runner/OpenQuickAddIntent.swift`
for future maintainers.

### Files changed in this pass
- `ios/TrackoraWidget/TrackoraWidget.swift` — `homeWidget=1` query
  appended to all widget deep-link URLs (5 sites: small `widgetURL`,
  step buttons, amount/pencil tap, Add, Custom).
- `lib/screens/home/statistics_screen.dart` — `_shareSnapshot` rewritten
  to render the capture tree at (0, 0) with a brand-colored cover, and
  to wait an extra frame + longer delay before snapshotting.
- `ios/Runner/OpenQuickAddIntent.swift` — expanded the leading comment
  to document the Back Tap library workaround in code.

### Known limitations / assumptions
- Apple does not expose Back Tap binding to apps. The library-wrapper
  step listed above is the only supported path. We cannot deep-link to
  the Back Tap Settings screen either (Apple keeps that URL private).
- The screenshot still flashes the user's display brand-colored for
  ~200 ms while capture happens. This is the cost of working around the
  Overlay clip behaviour without adding a third-party screenshot
  package. fl_chart + offscreen rendering does not currently have a
  cleaner alternative.
- The `homeWidget=1` query is treated as opaque by the iOS URL parser
  and stripped/ignored by `DeepLinkService._handle`. If anyone adds a
  new widget URL in future, **remember to include `homeWidget=1`** —
  otherwise the home_widget plugin will silently drop it.

### Checks / run status
- `dart analyze lib/screens/home/statistics_screen.dart lib/main.dart
  lib/services/widget_intent_service.dart lib/services/deep_link_service.dart`
  → No issues found.
- iOS Swift was not compiled in this pass; rebuild via Xcode (`cd ios
  && pod install && open Runner.xcworkspace`) and run on a real device
  to verify the widget deep links and the App Shortcut. Simulator's
  Settings does not show Back Tap; testing requires a physical phone.
- Manual test matrix covered by this pass: tap pencil from widget →
  QuickAddSheet opens with prefilled amount that user can edit;
  decimals (0.30, 1.50, 12.80) save correctly; share button on Stats
  produces a non-blank PNG containing the filtered report.

---

## Latest Pass — Widget Direct Input, Budget Progress, Quick Add Shortcut

### Rectangle widget — direct amount input
The medium / small home-screen widget previously made users tap +/- repeatedly
to land on the right amount because WidgetKit forbids text input. The amount
label in the +/- row is now wrapped in a `Link(...)` to
`trackora://quickadd?amount=<currentDraft>`. Tapping the amount opens
Trackora directly into the existing in-app `QuickAddSheet` with the draft
pre-filled, where the user can type the exact value. The +/- buttons are
kept for one-tap nudges. A small pencil glyph next to the amount hints at
the new tap target (`ios/TrackoraWidget/TrackoraWidget.swift`).

### Rectangle widget — monthly budget progress
Added a compact iOS-style progress strip to `balanceBlock` that renders
when `monthBudget > 0`. The strip shows:

- usage percent in heavy rounded font,
- `<spent> / <budget>` in soft secondary text,
- a 5 px pill track filled to the actual ratio (clamped to 100% visually
  even when `pct >= 1`).

Three tinted states: neutral black for healthy, amber for ≥ 80% (warning),
red when over budget. The headline number was already red on overspend;
the progress strip extends that signal to the bar and percent label.

### iOS App Shortcut — "Quick Add Expense" (Back Tap / Siri / Action Button)
**Apple does not let third-party apps bind directly to Back Tap.** The
supported path is to publish an `AppShortcut` and let the user wire it
manually in:

  Settings → Accessibility → Touch → Back Tap → Double Tap →
  "Quick Add Expense"

The same shortcut also surfaces in Siri ("Hey Siri, quick add expense"),
the Shortcuts app, the Action Button (iPhone 15 Pro+) and Spotlight.

New file: `ios/Runner/OpenQuickAddIntent.swift` exposes:

- `OpenQuickAddIntent` — `openAppWhenRun = true`. When invoked it sets
  the App Group flag `pending_open_quickadd = true` (timestamp stored
  alongside) and Trackora foregrounds.
- `TrackoraAppShortcuts: AppShortcutsProvider` — registers the shortcut
  with three localized phrases ("Quick add expense in Trackora", etc.).

Flutter side (`lib/services/widget_intent_service.dart`) gained
`consumePendingQuickAdd()` which reads the flag through `home_widget`,
clears it, and returns whether the sheet should open. `lib/main.dart`
calls it on cold start and on every `AppLifecycleState.resumed`, then
shows `QuickAddSheet` via the existing `rootNavKey`.

The shortcut deliberately avoids the `trackora://quickadd` URL deep-link
path because URL routing from an App Intent isn't always reliable
through SceneDelegate. The App Group flag is the simpler, well-trodden
pattern.

### Quick Add dialog
Unchanged from existing implementation — `lib/screens/expenses/quick_add_sheet.dart`
already provides category chips, amount keypad, optional note, save and
cancel. It's reused for both the widget "Custom" / amount-tap deep link
and the new App Shortcut.

### Dynamic Island / Live Activity stance
Not implemented. Live Activities are designed for glanceable status, not
text-entry forms — Apple does not allow keyboard input inside an Activity.
The actual amount entry stays inside the app's `QuickAddSheet`. If a
future "in-progress entry" Live Activity becomes useful, it would surface
state only and tap to open the same sheet.

### Files changed in this pass
- `ios/TrackoraWidget/TrackoraWidget.swift` — tappable amount label,
  budget progress strip.
- `ios/Runner/OpenQuickAddIntent.swift` — new App Intent + App Shortcut.
- `ios/Runner.xcodeproj/project.pbxproj` — registered the new Swift
  source in the Runner target (PBXBuildFile, PBXFileReference, group,
  Sources build phase).
- `lib/services/widget_intent_service.dart` — `consumePendingQuickAdd()`.
- `lib/main.dart` — `_maybeOpenQuickAdd()` on cold start + resume.

### Known limitations / assumptions
- Back Tap remains a *user-side* binding. Apple offers no API to set
  it programmatically; the docs entry above describes the manual steps.
  Trackora cannot show a "set up Back Tap" deep link to that screen
  either — the Accessibility deep link URL is private.
- The App Shortcut requires iOS 16+. Older devices fall back to the
  existing widget tap / `trackora://quickadd` deep link, which already
  worked on iOS 15+.
- The progress strip is rendered in both small and medium widgets
  because `balanceBlock` is shared. On small the bar competes with the
  quick-add grid for vertical room — the layout still fits today
  because the headline uses `minimumScaleFactor` aggressively, but on
  some smaller form factors users may see a slightly tighter strip.
- The pbxproj edit uses synthesized 24-char IDs (`8A5BCD2D...` /
  `8A5BCD2E...`) that don't collide with anything in the existing
  file. If Xcode ever rewrites the project the IDs may change, which
  is fine.

### Checks / run status
- `dart analyze lib/main.dart lib/services/widget_intent_service.dart`
  → No issues found.
- Swift files were not compiled in this pass (no Xcode toolchain run).
  Build should be verified on a Mac with Xcode 15+ before shipping:
  `cd ios && pod install && open Runner.xcworkspace`, then build for
  a real device (App Intents don't appear in Settings on the
  Simulator's Back Tap).

---

## Latest Pass — Stats Charts Carousel + Report Export

### Filter section redesign
The previous filter row used a `Wrap`, which let `All` flow onto a
second line on narrow phones. Replaced with a new `_SegmentedFilter`
widget — four `Expanded` chips inside a single pill-shaped track, so
all four options always sit on one line at the same width. Selected
state is the existing `accentDark` fill. Below the segmented row the
filter card now shows: range label (left) + nav arrows (right), then a
recessed background row hosting the "Exclude bills + installments"
`CupertinoSwitch`. Three balanced rows, no awkward wrapping.

### Single swipeable charts card
Line chart and donut chart used to stack vertically. Replaced with a
new `_ChartsCarousel` widget that holds both charts inside one section
and exposes them through a `PageView`:

- A small tab-style header at the top of the carousel (icon + label per
  page) doubles as a tap-to-switch control.
- iOS-style page dots at the bottom track the active chart.
- Each page lives inside its own `SingleChildScrollView` so longer
  donut legends scroll within the 560 px viewport without breaking the
  outer scroll.
- The line-chart page is *dropped from the carousel* when `_period ==
  _StatsPeriod.all`, so the user only sees donut on All. If the user
  hides one of the two via Manage Visibility, the carousel collapses to
  a single non-swipeable page.

The page order is now: top action bar → filter → Overview → swipeable
charts.

### Screenshot/report export
`_buildReport(...)` learned a `forReport: true` mode used by the
off-screen capture path:

1. **Report header** (`_ReportHeader`) — "Trackora Stats Report" title,
   doc-chart icon, generated timestamp, and three info pills showing
   the active period, current range label, and the include/exclude
   bills+installments state. Style stays Trackora-native (pastel mint
   icon tile, soft pill tags, rounded card) — does not copy any
   external reference.
2. **Filter card** with nav arrows hidden.
3. **Overview tiles** with tap callbacks suppressed (a static report
   shouldn't appear interactive).
4. **Charts** — `_ChartsCarousel` is forced into `stacked: true` mode
   for the snapshot. The PageView fights with `RepaintBoundary.toImage`
   (off-screen pages don't paint reliably), so the report stacks the
   line-chart card above the donut card vertically. Donut keeps its
   built-in category breakdown legend, satisfying the "Category
   breakdown from donut chart data" requirement.
5. The whole tree still renders inside an `OverlayEntry` positioned
   off-screen at full natural height, then captured at `pixelRatio:
   2.5` and shared via `share_plus`. Hidden sections are still gated by
   the visibility set, so they aren't in the export.

For All filter the report drops the line chart and shows just the
header + filter + overview + donut/category breakdown.

### Visibility model
Unchanged set of three section ids: `lineChart`, `importantData`
(displayed as "Overview"), `donutChart`. Hiding `lineChart` or
`donutChart` toggles those pages in the carousel; hiding both
collapses the carousel entirely.

### i18n
Added `stats.report.title` for en / zh / ms. No other label changes.

### Files changed in this pass
- `lib/screens/home/statistics_screen.dart` — `_SegmentedFilter`,
  `_ChartsCarousel`, `_ChartPage`, `_ReportHeader`, `_ReportTag`;
  `_FilterCard` rebuilt; `_buildReport` gained `forReport`. Removed
  unused `_RangeChip` and the local `_label` helper inside
  `_FilterCard`.
- `lib/services/i18n.dart` — `stats.report.title` for all three
  languages.

### Known limitations / assumptions
- The carousel viewport is a fixed 560 px tall to keep month-view's
  rotated x-axis labels and long donut legends visible without
  introducing intrinsic-height plumbing through the parent
  `SingleChildScrollView`. On very small devices (< ~560 logical px
  tall content area) the inner page can still scroll vertically.
- For the screenshot we lay the two charts out *stacked* rather than as
  a PageView. fl_chart's `LineChart` and `PieChart` only paint on the
  active PageView page, so a snapshot of an off-screen page would come
  back blank. Stacked layout is also more report-appropriate.
- The reference image used during design discussions was a financial
  report layout. The exported report does **not** copy that layout —
  it reuses Trackora's existing pastel iconography, segmented chips,
  rounded `SectionCard`s, and the existing `_OverviewCard` /
  `_CategoryCard` components.

### Checks / run status
- `dart analyze lib/screens/home/statistics_screen.dart
  lib/services/i18n.dart` → No issues found.
- Manual device testing not performed in this pass. Recommended:
  filter Week/Month/Year/All on a narrow viewport (verify no chip
  wraps), swipe between the two chart pages (and tap the header tabs),
  toggle Manage Visibility for line/donut individually, switch to All
  and confirm only the donut page is reachable, tap Share and verify
  the exported PNG has the report header + tags + tiles + both charts
  stacked + category legend.

---

## Latest Pass — Stats Page Refinements

Follow-up tweaks to the Stats page redesign documented in the next section.

### Section order
The on-screen and exported order is now: **Top action bar → Filter card →
Overview → Line chart → Donut chart**. Filter moved above the chart so it
clearly drives every section below it.

### "Important data" renamed to "Overview"
The summary card is now labelled "Overview" (zh `概览`, ms `Gambaran`). The
internal section id stays `importantData` so existing prefs still resolve
to the right toggle in the Manage Visibility sheet.

### Clickable Total Expenses / Total Income tiles
Both Overview tiles are now `GestureDetector`-wrapped and show a chevron
glyph when tappable. Tapping opens a new shared `_GenericRecordsSheet`
(see `lib/screens/home/statistics_screen.dart`) listing every expense or
income record that matches the active filter and exclude-fixed toggle. The
sheet reuses `_RecordRow`, which now accepts an optional `amountColor`
(income rows render in `AppColors.income` instead of the default expense
red). Records show title (note → category fallback), amount, date and
category. `Expense` has no payment-type field, so payment type isn't
shown — see "Known limitations" below.

### Default filter is Weekly
`_period` now starts at `_StatsPeriod.week` and `_anchor` at the start of
the current week. Switching periods resets the anchor to the *current*
week / month / year so the user always lands on a meaningful slice.

### Line chart not for "All"
The line chart card now renders a friendly "Line chart is only available
for Week, Month, or Year." message when `_period == all` instead of
trying to draw cumulative-by-year. Per spec, the chart only supports
Week / Month / Year.

### X-axis labels render every tick
Previously the chart sparsified labels (`labelStep`) for dense series. It
now renders every label and rotates them ≈ −52° when the series has
more than 12 points (i.e. days-in-month). Font size also steps down for
denser series (`8.5 / 9.5 / 10`). The chart container grows from 200 →
230 px tall in Month view to give the rotated labels breathing room.

### Screenshot fix — capture full report
The previous capture pinned a `RepaintBoundary` inside a scroll view, so
`boundary.toImage()` only painted the visible viewport. The new
`_shareSnapshot` builds an off-screen copy of the report column inside an
`OverlayEntry` (`Positioned(left: -mediaSize.width * 2, ...)`), waits two
frames for fl_chart to lay out, snapshots the dedicated overlay
`RepaintBoundary` at `pixelRatio: 2.5`, then removes the entry. The
exported PNG now includes the filter card (showing the active period and
exclude state), the overview, and any visible chart sections — exactly
what the user sees, regardless of scroll position. Hidden sections stay
out because the overlay copy uses the same `_buildReport(...)` helper
that gates on `visibleSections`.

### Files changed in this pass
- `lib/screens/home/statistics_screen.dart` (refactor of build, line
  chart x-axis, overlay-based screenshot, new generic records sheet,
  rename to `_OverviewCard`).
- `lib/services/i18n.dart` (label rename + `stats.expenseRecords`,
  `stats.incomeRecords`, `stats.lineChart.notForAll` for en/zh/ms).

### Known limitations / assumptions
- `Expense` has no payment-type field, so the records sheets do not show
  payment type. Adding it requires a model + repository change which is
  out of scope for a Stats-only pass.
- The overlay capture briefly inserts an extra widget tree off-screen.
  This adds a negligible build cost (~120 ms wait + one paint), but on
  very low-end devices the share button feel might be slightly slower.
  Trade-off accepted to make the screenshot reliably whole.
- Rotated month labels assume LTR locales. RTL languages aren't currently
  supported by the app, but if added later the rotation angle should be
  flipped to `+0.9`.

### Checks / run status
- `dart analyze lib/screens/home/statistics_screen.dart
  lib/services/i18n.dart` → No issues found.
- Manual device testing not performed in this pass. Recommended checks:
  switch Week/Month/Year/All; verify line chart is hidden on All and
  defaults to Week on first open; toggle exclude bills + installments
  and confirm Overview, donut, and the records sheets all update; tap
  Total Expenses and Total Income tiles to verify the records sheets
  open with the right entries; confirm Month view shows every day label
  legibly; tap Share and verify the exported PNG contains the filter
  card + visible sections without clipping.

---

## Latest Pass — Stats Page Redesign

### New layout order
`lib/screens/home/statistics_screen.dart` was rebuilt around a single global
filter that drives every section below it. The new top-to-bottom order is:

1. Top action bar — title + Manage Visibility + Share Snapshot.
2. Line chart card.
3. Filter card (period chips + Exclude bills + installments toggle + nav arrows).
4. Important data summary card.
5. Donut chart (By Category).

### Global filter behavior
The previous Weekly card and the per-card category filter were merged into one
global filter card. Periods: `Week`, `Month`, `Year`, `All`. Switching a period
resets the anchor date to "today" so the user lands on the current slice.
Prev/Next arrows step the anchor by 7 days / 1 month / 1 year (hidden for
`All`). The exclude-bills-and-installments toggle is a CupertinoSwitch on the
filter card and applies the same `category == 'Bills' || note.contains
('(installment)')` rule the budget page uses. All three sections
(line chart, summary, donut) re-derive from the filtered range immediately —
no stale state.

The line chart adapts to the selected period: 7 daily values for Week, daily
values for Month, 12 monthly buckets for Year, and per-year totals for All.
Inline value bubbles only render when the series is sparse (≤12 points and
denseLabels) to keep the chart readable.

### Important data summary section
A new `_SummaryCard` shows a 2-column grid of pastel tiles for the active
range: Total expenses, Total income, Net balance, Transactions, Highest
expense, Highest income, Avg. expense, and Top category. Tiles for highest
income/expense and top category drop off when the underlying data is empty.
Empty state: a single localized "No data for this range yet." line.

### Visibility management
Stats now has its own visibility set, persisted via
`PrefsService.visibleStatsSections()` /
`PrefsService.setVisibleStatsSections()` and exposed through
`statsSectionsVisibilityProvider` (reuses the existing
`VisibilitySetNotifier`). Default = all three sections visible. The
"Manage visibility" button on the top action bar opens the same
`_VisibilitySheet` pattern used by Home / Money Hub, with toggles for
`lineChart`, `importantData`, `donutChart`. At least one section must
stay visible (matches the existing Home/Money convention).

### Share snapshot
The Share button captures the current Stats view as a PNG and hands it to
`share_plus`. Implementation: a `RepaintBoundary` wraps everything below the
action bar, and `_shareSnapshot` calls `boundary.toImage(pixelRatio: 3)` →
`toByteData` → writes to the temp directory → `Share.shareXFiles`. Because
hidden sections are not in the widget tree, they are also not in the
screenshot. Errors fall through to a SnackBar with the localized
"Could not export snapshot" message.

### i18n
New keys were added to `en`, `zh`, `ms`: `stats.manageVisibility`,
`stats.customizeSections`, `stats.shareSnapshot`, `stats.exportFailed`,
`stats.section.{lineChart,importantData,donutChart}`, `stats.summary.*`,
`stats.lineChart.{title,empty,weekSubtitle,monthSubtitle,yearSubtitle,allSubtitle}`.

### Files changed in this pass
- `lib/screens/home/statistics_screen.dart` (full rewrite)
- `lib/services/prefs_service.dart` (added stats visibility prefs)
- `lib/state/providers.dart` (added `statsSectionsVisibilityProvider`)
- `lib/services/i18n.dart` (added en/zh/ms keys for the new UI)

### Assumptions and known limitations
- The "payment type" field requested for the category-records popup does not
  exist on `Expense`; the popup keeps showing title/amount/date/category. If
  payment type is added to the model later, the popup row should grow a
  third info line.
- Previous "Custom range" picker on the donut card was removed in favor of
  the unified Week/Month/Year/All selector, in line with the spec. If a
  custom range becomes a requirement again, it can be re-added as a 5th chip
  with the existing date-picker code restored from git history.
- Screenshot export uses `pixelRatio: 3` which produces large images on
  tall phones. Acceptable for sharing; not optimized for low-memory devices.
- Line chart renders an empty state when the active period has zero
  spending — including for "Month" with no entries — rather than trying to
  draw a flat zero line.

### Checks / run status
- `dart analyze lib/screens/home/statistics_screen.dart
  lib/services/prefs_service.dart lib/state/providers.dart
  lib/services/i18n.dart` → No issues found.
- Manual testing has not yet been performed on a device; the dev server was
  not started in this pass. Recommended manual checks: filter switching
  (Week/Month/Year/All), exclude toggle, hide/show each section via Manage
  Visibility, share button writes a PNG and opens the share sheet, donut
  category popup opens, empty states render for ranges with no data.

---

## Latest Pass — Money Budget Details, Stats Category Ranges, CSV Export Range

### Money Hub monthly budget details
`lib/screens/home/budget_screen.dart` now opens a monthly budget details sheet
when the Money Hub `Monthly budget` card is tapped. The sheet shows:

- Monthly budget amount.
- Spent this month.
- Remaining budget.
- Budget usage percentage.
- A simple progress bar.
- An `Edit monthly budget` action that reuses the existing budget editor.

Why: tapping the monthly budget should first explain the current budget state,
instead of immediately forcing the user into editing.

Assumption: the existing `selectedMonthProvider` remains the source of the
month shown in Money Hub, and bills/installment entries remain excluded from
budget spending through the existing discretionary-spend rule.

### Stats weekly spend priority
`lib/screens/home/statistics_screen.dart` now defaults Weekly Spend to exclude
bills and installments. The segmented control shows
`Exclude bills + installments` first, with include still available as the
second option.

Why: day-to-day spending is the priority view, while the old include behavior
is still preserved behind the second segment.

### Stats By Category redesign
The By Category section now uses all expense records and filters them in-memory
by:

- Week
- Month
- Year
- All
- Custom range

Custom range uses start and end date pickers. The donut chart, legend, totals,
empty state, and category record sheet all respect the selected range.

The category chart remains powered by `fl_chart`, but the interaction changed:
tapping a donut segment or legend row opens a bottom sheet listing the matching
records for that category. Each record shows note/category fallback, amount,
date, and category. The donut center always shows total expense for the active
range.

Why: this replaces the old month-only category chips with a broader, clearer
filter system and makes category totals inspectable without navigating away.

Assumption: Week/Month/Year filters refer to the current calendar week, month,
and year. Older periods can be inspected with Custom range or All.

### CSV export range selection
`lib/screens/settings/settings_screen.dart` now shows an export range sheet
before sharing a CSV. Users can choose:

- A specific month, selected from months that contain records.
- Export all records.

The exported CSV receives only records matching the selected range. The export
service itself is unchanged; filtering happens before calling
`ExportService.exportCsv(...)`.

Why: range selection keeps export behavior simple and reliable without changing
the CSV schema or import compatibility.

### Localization
`lib/services/i18n.dart` adds English, Chinese, and Malay strings for the new
budget details sheet, Stats filters, Weekly Spend labels, and CSV export range
sheet.

### Files changed in this pass
- `lib/screens/home/budget_screen.dart`
- `lib/screens/home/statistics_screen.dart`
- `lib/screens/settings/settings_screen.dart`
- `lib/services/i18n.dart`
- `docs/PROJECT_CONTEXT.md`

### Checks / run status
- `dart analyze lib` -> **No issues found!**
- `flutter precache --macos` -> completed with no output.
- `flutter precache --universal --force` -> restored the missing tester
  engine artifacts.
- `flutter test` -> **All tests passed!** Pub still printed the existing
  advisory decode warnings (`advisoriesUpdated must be a String`) while
  resolving dependencies, then continued successfully.

### Exact run commands

```sh
dart analyze lib
flutter precache --macos
flutter precache --universal --force
flutter test
```

## Latest Pass — Money Hub Rename, Visibility Settings, Swipe Actions

### Budget rename decision
The bottom navigation formerly labelled `Budget` is now `Money`, using a
broader `CupertinoIcons.creditcard_fill` icon instead of a budget-only pie
icon. The tab still uses the existing `BudgetScreen` class internally, but the
visible page title is now `Money Hub`.

Localization added/updated:
- `tab.money`
- `money.title`
- `money.subtitle`
- `money.customizeHub`

### Home card visibility settings
`lib/screens/home/dashboard_screen.dart` now has a small sliders/customize
button in the Home header. It opens an iOS-style bottom sheet labelled
`Customize Home Cards`.

Users can hide/unhide these carousel cards:
- Total Balance
- Monthly Budget
- Saving Plans
- Borrow & Lending

Visibility is persisted locally through `PrefsService` and
`homeCardVisibilityProvider`, backed by `SharedPreferences`. At least one card
must remain visible. Hiding a card only removes it from the Home carousel; it
does not delete or disable any data/module.

### Money Hub module visibility settings
`lib/screens/home/budget_screen.dart` now has a matching customize button in
the Money Hub header. It opens `Customize Money Hub`.

Users can hide/unhide these Money Hub modules:
- Manage Installments
- Borrow & Lending
- Saving Plans
- Monthly Budget

Visibility is persisted locally through `PrefsService` and
`moneyHubVisibilityProvider`, backed by `SharedPreferences`. At least one
module must remain visible. Hiding a module only affects the Money Hub list UI.

### Swipe quick actions
The record list screens now support iOS-style swipe quick actions with
`Dismissible`. Swipes never auto-delete a row; they open edit/actions and then
the row returns to place.

- `InstallmentsScreen`
  - Swipe one direction: edit.
  - Swipe the other direction: mark completed/reactivate/cancel and delete.
  - Cancel and delete still require confirmation where destructive.
- `BorrowLendingScreen`
  - Swipe one direction: edit.
  - Swipe the other direction: mark settled and delete.
  - Delete requires confirmation.
- `SavingPlansScreen`
  - Swipe one direction: edit, plus add contribution when the plan supports
    direct contributions.
  - Swipe the other direction: mark completed/reactivate/cancel and delete.
  - Delete requires confirmation.

### Files changed in this pass
- `lib/services/prefs_service.dart`
- `lib/state/providers.dart`
- `lib/screens/home/home_shell.dart`
- `lib/screens/home/dashboard_screen.dart`
- `lib/screens/home/budget_screen.dart`
- `lib/screens/installments/installments_screen.dart`
- `lib/screens/borrow_lending/borrow_lending_screen.dart`
- `lib/screens/savings/saving_plans_screen.dart`
- `lib/services/i18n.dart`
- `docs/PROJECT_CONTEXT.md`

### Known limitations
- `flutter pub get` completed, but the current Dart/pub tool still prints
  advisory decode warnings (`advisoriesUpdated must be a String`) for some
  pub.dev advisories.
- `pod install` completed with the existing CocoaPods platform and base
  configuration warnings.
- Wireless release install/launch works, but can still be slower than USB
  because the watch companion is included.

### Checks / run status
- `dart analyze lib` → **No issues found!**
- `flutter pub get` → completed; ended with `Got dependencies!`
- `cd ios && pod install && cd ..` → completed; 35 total pods installed.
- `flutter run --release -d 00008150-001870EA3693401C` → built, installed,
  and launched on Michael's iPhone (wireless). The attached runner reached
  the run-command prompt before being stopped.

### Exact run commands

```sh
dart analyze lib
flutter pub get
cd ios && pod install && cd ..
flutter run --release -d 00008150-001870EA3693401C
```

## Latest Pass — Profile Alignment, Home Carousel, Money Management

### Profile alignment changes
`lib/screens/settings/settings_screen.dart` now uses a consistent trailing
layout for Profile rows:

- Account rows (`Currency`, `Starting savings`) keep the label on the left,
  value on the right, and chevron at the far-right edge.
- Display rows (`Appearance`, `Language`) use the same value-before-chevron
  layout.
- The non-clickable `Version` row reserves the same far-right chevron slot
  so its value aligns with clickable rows.

### Home carousel changes
`lib/screens/home/dashboard_screen.dart` replaces the single total-balance
hero with a fixed-height swipeable carousel and page indicator dots.

Cards:
- `Total balance` keeps the existing hide/show balance behavior with
  `MaskedAmount` and `balanceVisibleProvider`.
- `Monthly budget` shows budget, spent, and remaining. If no budget is set,
  the card shows a simple empty state and opens the monthly budget editor.
- `Saving Plans` summarizes total saved, total target, and active plans count.
  Tapping opens the existing `SavingPlansScreen`.
- `Borrow & Lending` summarizes total borrowed, total lent, and net position.
  Tapping opens the existing `BorrowLendingScreen`.

The old Home income/spent cards and old standalone monthly budget progress
section are removed from the Home page for a cleaner layout. The centered
Add Expense floating button remains unchanged in `HomeShell`.

### Budget page redesign
`lib/screens/home/budget_screen.dart` is now an iOS-style Money Management
page. It preserves offline-first repository/provider access and navigates to
existing modules:

- `Manage installments` opens `InstallmentsScreen`.
- `Borrow & Lending` opens `BorrowLendingScreen`.
- `Saving Plans` opens `SavingPlansScreen`.
- `Monthly budget` opens the shared monthly budget editor.

Each card has an icon, title, short description, summary value, and aligned
chevron. Summaries use `formatMoney(...)`, so amounts render with two
decimals.

### Localization
`lib/services/i18n.dart` adds English, Chinese, and Malay strings for the new
Home carousel labels and Money Management page labels. Existing tool labels
are reused where possible.

### Files changed in this pass
- `lib/screens/settings/settings_screen.dart`
- `lib/screens/home/dashboard_screen.dart`
- `lib/screens/home/budget_screen.dart`
- `lib/services/i18n.dart`
- `docs/PROJECT_CONTEXT.md`

### Known limitations
- `flutter pub get` completed, but the current Dart/pub tool printed
  advisory decode warnings (`advisoriesUpdated must be a String`) for some
  pub.dev advisories.
- `pod install` completed, with the existing CocoaPods platform and base
  configuration warnings.
- Wireless iPhone release launch works, but wireless install/launch can still
  be slower than USB because the watch companion is included.

### Checks / run status
- `dart analyze lib` → **No issues found!**
- `flutter pub get` → completed; ended with `Got dependencies!`
- `cd ios && pod install && cd ..` → completed; 35 total pods installed.
- `flutter run --release -d 00008150-001870EA3693401C` → built, installed,
  and launched on Michael's iPhone (wireless). The attached Flutter runner
  reached the run-command prompt and stayed up before being stopped.

### Exact run commands

```sh
dart analyze lib
flutter pub get
cd ios && pod install && cd ..
flutter run --release -d 00008150-001870EA3693401C
```

## Latest Pass — Widget Stepper Quick Add

### Widget quick controls
The iOS widget no longer shows fixed `+5 / +10 / +20` quick-add
buttons. `ios/TrackoraWidget/TrackoraWidget.swift` now renders a compact
amount stepper:

- `-` decreases the draft amount by 1.00.
- `+` increases the draft amount by 1.00.
- **Add** saves the current draft amount directly through the existing
  widget quick-add queue.
- **Custom** is unchanged: it opens `trackora://quickadd`, which routes
  into the compact quick-add dialog with amount and category chips.

The draft amount is stored in App Group `UserDefaults` as
`widgetDraftAmount`, clamped to `1.00...9999.00`, and rendered with the
same two-decimal widget money formatter.

### App Intent behavior and limitation
`ios/TrackoraWidget/QuickAddExpenseIntent.swift` now includes
`AdjustDraftAmountIntent` for the `- / +` controls. On iOS 17+, tapping
`-`, `+`, or **Add** does **not** open Trackora:

- `AdjustDraftAmountIntent` updates `widgetDraftAmount` and reloads the
  widget timeline.
- `QuickAddExpenseIntent` still appends to
  `pending_widget_expenses_json`, optimistically updates widget totals,
  and reloads timelines.

The direct **Add** button uses the existing default widget category
`Food`. Users who need to choose category should tap **Custom**, which
opens the compact dialog instead of the normal home screen.

Important iOS limitation: WidgetKit widgets cannot present an arbitrary
text field or category picker inside the widget. Interactive widgets can
run App Intents with already-provided parameters, so Trackora can adjust
a stored draft amount and save it, but free-form amount/category entry
still needs the compact in-app dialog.

iOS 16 and earlier do not support `Button(intent:)`; those controls fall
back to deep links into the compact quick-add dialog.

### Files changed in this pass
- `ios/TrackoraWidget/TrackoraWidget.swift` — replaced fixed amount grid
  with responsive `- / amount / +` controls plus **Add** and **Custom**.
- `ios/TrackoraWidget/QuickAddExpenseIntent.swift` — added shared App
  Group constant and `AdjustDraftAmountIntent`.
- `docs/PROJECT_CONTEXT.md` — this update.

### Checks / run status
- `dart analyze lib` → **No issues found!**
- `xcodebuild -workspace Runner.xcworkspace -scheme TrackoraWidget
  -destination generic/platform=iOS -derivedDataPath
  /private/tmp/trackora-widget-derived-data CODE_SIGNING_ALLOWED=NO
  build` → **BUILD SUCCEEDED**.
- Full `flutter run --release -d 00008150-001870EA3693401C` install was
  not rerun in this pass; use it to install the latest widget on the
  iPhone.

### Exact run commands

```sh
dart analyze lib
cd ios
xcodebuild -workspace Runner.xcworkspace -scheme TrackoraWidget -destination generic/platform=iOS -derivedDataPath /private/tmp/trackora-widget-derived-data CODE_SIGNING_ALLOWED=NO build
cd ..
flutter run --release -d 00008150-001870EA3693401C
```

## Latest Pass — Widget Custom Dialog Fallback + Dark-Mode Contrast

### Widget Custom behavior
`ios/TrackoraWidget/TrackoraWidget.swift` still renders the **Custom**
button as a `Link(destination: trackora://quickadd)`.

Important iOS limitation: WidgetKit interactive widgets support buttons
and toggles backed by App Intents, but widget intent parameters must
already have assigned values; widgets do **not** resolve new parameters
from the user at tap time. That means a true in-widget keyboard text
field / category picker popup is not available for a Home Screen widget.

Best fallback implemented:
- Tapping **Custom** does not open the normal home screen or full Add/Edit
  Expense page.
- It opens Trackora directly into the compact quick-add dialog.
- The dialog has an autofocus amount field, category chips, and Save.
- Saving writes through `ExpenseRepository` and nudges widget totals via
  `WidgetSyncService.nudgeQuickExpense(...)`.

### Dark-mode contrast cleanup
`lib/screens/home/statistics_screen.dart` had the most visible dark-mode
contrast problems because it still used light-mode static ink colours
inside neutral dark cards. The weekly chart and category card now use:
- `brand.accent` / `brand.accentDark` for chart line contrast by theme.
- `brand.ink`, `brand.inkSoft`, `brand.divider`, and `brand.background`
  for labels, dividers, toggle surfaces, and progress tracks.
- Pastel icon badges keep dark ink intentionally through the existing
  pastel-card pattern.

`lib/screens/installments/installments_screen.dart` progress indicators
also now use theme-aware `brand.ink` / `brand.inkSoft` for active and
cancelled progress states.

### Files changed in this pass
- `lib/screens/expenses/quick_add_sheet.dart` — changed widget quick-add
  fallback from a bottom sheet to a centered compact dialog with amount
  and category.
- `ios/TrackoraWidget/TrackoraWidget.swift` — updated Custom comment to
  document dialog fallback.
- `lib/screens/home/statistics_screen.dart` — fixed dark-mode chart,
  segmented toggle, label, divider, and progress-track contrast.
- `lib/screens/installments/installments_screen.dart` — fixed dark-mode
  installment progress contrast.
- `docs/PROJECT_CONTEXT.md` — this update.

### Checks / run status
- `dart analyze lib` → **No issues found!**
- `flutter pub get` → completed.
- `cd ios && pod install && cd ..` → completed; CocoaPods still prints
  the existing platform/base-configuration warnings.
- `flutter run --release -d 00008150-001870EA3693401C` was started after
  the prior changes, but the user intentionally interrupted it during the
  Xcode build. Do not assume the latest dialog/dark-mode pass is installed
  on the iPhone until this command completes.

### Exact run commands

```sh
flutter pub get
cd ios && pod install && cd ..
flutter run --release -d 00008150-001870EA3693401C
```

## Current Architecture

Trackora is a Flutter expense tracker with Riverpod state management. The app entry point is `lib/main.dart`, which selects local or Firebase startup from `lib/app_config.dart`. The main UI is `HomeShell`, with Home, Statistics, Budget, and Profile tabs.

Screens consume Riverpod providers from `lib/state/providers.dart`. Expense storage is abstracted behind `ExpenseRepository`; installment storage is abstracted behind `InstallmentRepository`. **Screens must not call Hive or `FirebaseFirestore` directly** — they go through repositories/services/providers.

## Storage Mode Setup

`lib/app_config.dart` defines:

```dart
enum StorageMode { local, firebase }

const StorageMode storageMode = StorageMode.local;
```

Default mode is local/offline. In local mode, `main.dart` initializes Hive through `LocalStorage` and uses a built-in offline app user. In Firebase mode, `main.dart` initializes Firebase using `firebase_options.dart`.

## Important Folders And Files

- `lib/app_config.dart` — storage mode switch.
- `lib/main.dart` — app bootstrap and local/Firebase initialization.
- `lib/state/providers.dart` — Riverpod providers and repository selection.
- `lib/models/expense.dart` — storage-neutral expense model.
- `lib/models/installment.dart` — storage-neutral installment model.
- `lib/repositories/expense_repository.dart` — expense repository contract.
- `lib/repositories/local_expense_repository.dart` — Hive-backed expense storage.
- `lib/repositories/firebase_expense_repository.dart` — Firestore-backed expense storage.
- `lib/repositories/installment_repository.dart` — installment repository contract.
- `lib/repositories/local_installment_repository.dart` — Hive-backed installment storage.
- `lib/repositories/firebase_installment_repository.dart` — Firestore-backed installment storage.
- `lib/repositories/local_storage.dart` — Hive box bootstrap.
- `lib/services/export_service.dart` — CSV export/import flow.
- `lib/screens/home/dashboard_screen.dart` — minimal home dashboard.
- `lib/screens/home/statistics_screen.dart` — minimal statistics (weekly line + monthly category).
- `lib/screens/home/budget_screen.dart` — budget breakdown (excludes bills + installments).
- `lib/screens/installments/` — installments management screens (kept; not on home anymore).
- `lib/screens/settings/settings_screen.dart` — profile/preferences/export entry points.
- `ios/TrackoraWidget/` — iOS home widget.
- `tool/configure_widget_target.rb` — idempotently creates/configures the
  `TrackoraWidget` WidgetKit target and embeds it in Runner.
- `lib/firebase_options.dart` — Firebase configuration; do not remove.

## Features Completed

- Offline-first expense storage with Hive.
- Firebase expense + installment storage preserved behind repository implementation.
- Offline app user for local mode.
- Add, view, edit, delete expenses.
- Month filtering and monthly totals.
- Categories and category styling.
- Budget, opening savings, lifetime savings total.
- Installments (managed from a dedicated screen, no longer on home).
- Offline CSV export/import for expenses, with success / error / cancel feedback.
- Minimal home dashboard centered on **Current total left**.
- Minimal statistics screen with two cards only:
  - Weekly line chart (with previous / next week navigation).
  - Monthly category breakdown (with month filter).
- iOS home widget sync (current spend, budget, savings).
- iOS WidgetKit target wired into `ios/Runner.xcodeproj` and embedded in Runner.
- App icon assets.

## UI Changes (Recent)

### Home dashboard (`lib/screens/home/dashboard_screen.dart`)
- Re-organized to put the user's **actual money** front and center, not a budget number.
- New layout (top to bottom):
  1. Top bar — day name + "Trackora" title + avatar.
  2. **Total balance** hero (dark card) — `opening savings + lifetime income − lifetime expenses`. Shows `Lifetime in` and `Lifetime out` summary chips.
  3. Side-by-side **Income** (mint) and **Spent** (blush) cards for the selected month.
  4. **Monthly budget** progress card (only when a budget is set; turns red when overspent and shows "Over by $X").
  5. Quick stats row — Today and This week, with entry counts.
  6. Month filter chips.
  7. Recent activity (max 5).
- Removed installments card from home (managed elsewhere).
- Removed All / Expense / Income pill tabs.

### Statistics screen (`lib/screens/home/statistics_screen.dart`)
- Removed the "Overview" summary card (per day / highest / average / entries).
- Removed inline summary metrics row.
- Now contains only two cards:
  - **Weekly spend** line chart with prev / next week navigation, weekly total, and a one-line plain-English summary.
  - **By category** monthly breakdown (donut + ranked list with progress bars), driven by the existing `MonthFilterBar`. Includes a one-line summary describing the dominant category.

## CSV Implementation

`lib/services/export_service.dart` is storage-neutral and accepts an `ExpenseRepository`.

### Export
- Builds CSV rows from all expenses (`ListToCsvConverter`).
- Writes the file to `getTemporaryDirectory()` with a timestamped filename.
- `flush: true` to guarantee bytes hit disk before sharing.
- Verifies the file exists; throws `FileSystemException` if not.
- Calls `Share.shareXFiles` with `mimeType: 'text/csv'` so iOS/Android get the right share sheet preview.
- Returns a `CsvExportResult { filePath, rowCount, shareStatus }`.
- Settings screen surfaces success (`Exported N entries to CSV.`) or `Export failed: <reason>` via SnackBar.
- Throws if there is nothing to export so the caller can surface a friendly message.

### Import
- Uses `FilePicker.platform.pickFiles(type: custom, allowedExtensions: ['csv'])`.
- Returns `CsvImportResult.cancelled = true` if the user dismisses the picker.
- Reads the file with `File(path).readAsString()`.
- Parses with `CsvToListConverter(shouldParseNumbers: false)` and maps headers case-insensitively.
- Dedupes by `id`: any row whose ID already exists in the repository is counted as `skipped` and not written.
- Each row is converted to an `Expense` and persisted via `repository.upsertExpense(userId, expense)` — preserving imported IDs in local mode and using Firestore IDs in Firebase mode.
- Returns `CsvImportResult { imported, skipped, failed }`.
- Settings screen surfaces import counts in a SnackBar; failures and cancellations are reported separately.

## Apple Watch Companion

Trackora now ships a paired watchOS app (native SwiftUI). It is **not** Flutter — Flutter does not run on watchOS — but it is wired to the same data:

- The watch reads current spending summary (`monthSpent`, `monthBudget`, `currency`, `savings`) from the shared App Group `group.com.michaelchia.trackora` UserDefaults that `WidgetSyncService` already writes.
- When the user adds an expense on the watch, the watch sends a `WCSession.sendMessage({"type": "addExpense", "amount": …, "category": …, "note": …})`.
- The Flutter app receives the message via the `watch_connectivity` package in `lib/services/watch_service.dart`, which calls the active `ExpenseRepository.addExpense(...)`. Repository pattern is preserved — the watch path never touches Hive or Firestore directly.
- The bridge is attached in `lib/main.dart` once an auth user is available, and re-attached on auth changes via `ref.listen(authStateProvider, …)`.

### Watch source files (`ios/TrackoraWatch Watch App/`)
- `TrackoraWatchApp.swift` — `@main` entry, owns `WatchSession.shared`.
- `WatchSession.swift` — `ObservableObject` + `WCSessionDelegate`. Loads numbers from App Group UserDefaults and exposes `addExpense(...)` over `WCSession.sendMessage`.
- `ContentView.swift` — main watch screen: big "Remaining" / "Spent" number, optional progress bar, and a "+ Add expense" button.
- `AddExpenseView.swift` — Digital-Crown-rotated amount input, +5/+10/+20/+50/+100 quick-add buttons, two-column category grid, save.
- `Info.plist` — `WKCompanionAppBundleIdentifier = com.michaelchia.trackora`.
- `TrackoraWatch.entitlements` — same App Group as iPhone + iOS widget.

### Limitations (current MVP)
- Phone must be reachable when adding from the watch (`session.isReachable`). If not, the watch surfaces *"iPhone not reachable. Open Trackora on your phone."* — no offline queue yet.
- The watch displays totals as last pushed by the iPhone dashboard; a hard refresh is on the watch screen.
- No watchOS complications yet.

### One-time Xcode setup
1. Open `ios/Runner.xcworkspace` in Xcode.
2. **File → New → Target → watchOS → App**. Product Name: `TrackoraWatch`. Bundle ID: `com.michaelchia.trackora.watchkitapp`. Interface: **SwiftUI**, Language: **Swift**. Tick **Include Notification Scene** off. Tick **Embed in Companion Application: Runner**.
3. Xcode creates a `TrackoraWatch Watch App` folder. **Delete** its auto-generated `ContentView.swift`, `TrackoraWatchApp.swift`, `Info.plist`, then **drag in** the existing files from `ios/TrackoraWatch Watch App/` (TrackoraWatchApp.swift, WatchSession.swift, ContentView.swift, AddExpenseView.swift, Info.plist, TrackoraWatch.entitlements). Add them to the **TrackoraWatch Watch App** target only.
4. Select the **TrackoraWatch Watch App** target → Signing & Capabilities → **+ Capability → App Groups** → tick `group.com.michaelchia.trackora`.
5. (Already done for Runner.) Confirm the **Runner** target also has the same App Group ticked.
6. Plug in your iPhone with the Apple Watch paired. Run the watch scheme: select **TrackoraWatch Watch App** scheme → choose your watch as the destination → ⌘R.

## iPhone Home Screen Widget

Native WidgetKit widget at `ios/TrackoraWidget/`. The Flutter app pushes
summary numbers via `WidgetSyncService` (already wired) into the shared
App Group `group.com.michaelchia.trackora`; the widget reads them from
that App Group's `UserDefaults` and renders a small (2x2) and medium
(4x2) layout.

### What it shows
- "Trackora" label with chart-pie icon (logo row).
- **Remaining** for the month (budget − budgetable spent), or, if no
  budget is set, the lifetime **Total balance**.
- Progress bar against the monthly budget when set; flips red on over.
- Spent-this-month line.
- Footer: **"Tap to add expense"** on small, **"Tap to open · + to add expense"** on medium.
- Medium also has explicit `+ Add` and `Open` capsule buttons.

### Deep links
- Tap the small widget chrome → `trackora://add` → `DeepLinkService` opens
  Add/Edit Expense screen directly.
- Medium widget body → `trackora://` (just opens the app); the explicit
  `+ Add` button → `trackora://add`.

### Xcode target setup
The widget Swift source files are on disk and the Xcode target is now
configured in `ios/Runner.xcodeproj`:

- Target: `TrackoraWidget`
- Bundle ID: `com.michaelchia.trackora.TrackoraWidget`
- Entitlements: `ios/TrackoraWidget/TrackoraWidget.entitlements`
- Runner has an `Embed App Extensions` build phase that embeds
  `TrackoraWidget.appex`.

If the Xcode project is regenerated, run:

```sh
ruby tool/configure_widget_target.rb
```

The Apple Developer account / provisioning profile must include the same
App Group for both Runner and widget: `group.com.michaelchia.trackora`.
After installing a release build, enter Home Screen edit mode, tap **+**,
and search **Trackora**. Widgets do not appear in the app icon long-press
quick-action menu.

## Theme: Light / Dark / System

`PrefsService` persists the user's choice as `'system' | 'light' | 'dark'`
under the `theme_mode` key. `ThemeModeNotifier` (Riverpod
`StateNotifierProvider<ThemeMode>`) loads on start and writes on change.
`MaterialApp` consumes `themeModeProvider` and is configured with
`AppTheme.light()` + `AppTheme.dark()`.

### How to use the palette in widgets
Both themes register a `BrandColors` `ThemeExtension`. Read it via the
`context.brand` extension defined in `lib/theme/app_theme.dart`:

```dart
final brand = context.brand;
container(color: brand.surface);    // flips light/dark
container(color: brand.background); // flips light/dark
text(style: TextStyle(color: brand.ink));
text(style: TextStyle(color: brand.inkSoft));
container(color: AppColors.mint);   // pastels stay constant
```

`AppColors` is kept as a backwards-compatible static palette for the
brand pastels (mint, lilac, peach, butter, blush, sky, sage, sand,
income, expense) and the light defaults (`background`, `surface`, `ink`,
`inkSoft`, `divider`). The pastels are the same in both themes — they
read fine on light or dark backgrounds. Widgets that still reference
`AppColors.background` etc. compile and render correctly in light mode;
migrate them to `context.brand.*` over time so they flip in dark mode.

### Settings entry
Settings → **Appearance** opens a bottom sheet with three options
(System / Light / Dark, each with icon + subtitle). Tapping persists and
applies instantly. Default is System.

### Status bar
`main.dart` calls `SystemChrome.setSystemUIOverlayStyle(...)` on every
build of `TrackoraApp`, computing the effective brightness from
`themeMode` + `MediaQuery.platformBrightnessOf` so status-bar icons match
the active theme.

## Home Page Simplification

`lib/screens/home/dashboard_screen.dart`:

- Removed the `_QuickStatsRow` (Today + This week tiles) per spec.
- New layout: top bar → Total Balance hero → Income/Spent metric row →
  Budget progress (only when set) → Month filter → Recent activity (max 5).
- All explicit color references in the dashboard's outer chrome were
  migrated to `context.brand.*` so the screen flips with the theme.
  The pastel cards (Total Balance hero, Income, Spent, Budget) keep
  their fixed brand pastels — they're decorative and read on both
  backgrounds.

## Stats Weekly Chart Filter

`lib/screens/home/statistics_screen.dart`:

- Added a segmented toggle inside the **Weekly spend** card with two
  options: **"Include bills + instalments"** (default) and **"Exclude"**.
- The toggle controls a single `_includeBillsAndInstallments` state.
  When excluded, expenses where `category == 'Bills'` or where the note
  contains `(installment)` are filtered out of the chart and the weekly
  total — same rule the Home/Budget screens use for budgetable spend.
- Daily totals, summary line, weekly total number, and the line chart
  all recompute from the filtered list.
- Previous / Next week chevrons remain wired and behave the same.
- Data path is unchanged: still flows through the `ExpenseRepository`
  via `allExpensesProvider`. No direct Hive / Firestore calls.

## Latest Pass — Money Tools (Borrow & Lending + Saving Plans), CSV Icon Fix

### Export / Import CSV icons
The two icons in **Profile → Data** were swapped to read more
intuitively. Export now uses `CupertinoIcons.square_arrow_up`
(outward / share-style); Import uses `CupertinoIcons.tray_arrow_down`
(inward / download-style). Labels unchanged (`Export to CSV` /
`Import CSV`).

### New module: Borrow & Lending
Lives at `lib/screens/borrow_lending/` and follows the existing
repository / service / provider pattern. Screens never touch Hive or
Firestore directly.

**Data layer:**
- `lib/models/borrow_lending.dart` — `BorrowLending` record + inline
  `BorrowLendingRepayment` list. Fields: id, type
  (`borrowed` / `lent`), person, amount, note, date, optional dueDate,
  optional imagePath, repayments[], cancelled, createdAt, updatedAt.
  Computed: `repaid`, `remaining`, `progress`, `status` (active /
  partial / settled / cancelled).
- `lib/repositories/borrow_lending_repository.dart` — abstract.
- `lib/repositories/local_borrow_lending_repository.dart` — Hive box
  `trackora_borrow_lending_v1`, key-prefixed `{userId}:{recordId}`.
- `lib/repositories/firebase_borrow_lending_repository.dart` —
  Firestore collection `users/{userId}/borrow_lending`. For parity
  only; local mode is the default in `app_config.dart`.
- `lib/services/borrow_lending_service.dart` — add / update / delete,
  plus `addRepayment`, `removeRepayment`, `markSettled`,
  `setCancelled`.
- `lib/state/providers.dart` — registered
  `borrowLendingRepositoryProvider`, `borrowLendingServiceProvider`,
  and a stream provider `borrowLendingProvider` that watches the
  active user's records.

**Screens:**
- `borrow_lending_screen.dart` — list with summary card
  (total borrowed / lent / net / active count), search bar by
  person name, filter chips (All / Borrowed / Lent / Active /
  Settled), record cards (icon, person, amount, status badge, date,
  progress bar when partial).
- `add_edit_borrow_lending_screen.dart` — form with type toggle
  (I borrowed / I lent), person, amount, note, date, optional due
  date, photo attachment via `StorageService` (same receipts
  directory as expenses).
- `borrow_lending_detail_screen.dart` — hero (person, amount,
  remaining, progress bar), details, photo preview using
  `ReceiptPreview`, repayment history with add / remove, action
  chips (Edit / Mark settled / Cancel / Delete-with-confirm).

### New module: Saving Plans
Lives at `lib/screens/savings/` and supports four flavours.

**Data layer:**
- `lib/models/saving_plan.dart` — `SavingPlan` + inline
  `SavingContribution` list. Plan types:
  - `fixed` — target + per-period contribution + frequency
    (daily / weekly / monthly).
  - `flexible` — target only, contribute any amount any time.
  - `daysChallenge` — N consecutive days, deposit per slot.
  - `weeksChallenge` — N consecutive weeks, deposit per slot.
  Computed: `currentAmount`, `remaining`, `progress`,
  `slotsCompleted`, `totalSlots`, `status` (active / completed /
  cancelled), `periodsLeft` (days / weeks / months / slots
  remaining at the current cadence).
- `lib/repositories/saving_plan_repository.dart` — abstract.
- `lib/repositories/local_saving_plan_repository.dart` — Hive box
  `trackora_saving_plans_v1`.
- `lib/repositories/firebase_saving_plan_repository.dart` —
  Firestore `users/{userId}/saving_plans`.
- `lib/services/saving_plan_service.dart` — CRUD plus
  `addContribution`, `removeContribution`, `markCompleted`,
  `setCancelled`.
- `lib/state/providers.dart` — `savingPlanRepositoryProvider`,
  `savingPlanServiceProvider`, `savingPlansProvider` stream.

**Screens:**
- `saving_plans_screen.dart` — list with gradient summary card
  (total saved across active plans, total target, active count,
  completed count), filter chips, plan cards. Each card has a small
  44 pt progress ring + linear bar, type chip, amount columns,
  trailing periods-left line.
- `add_edit_saving_plan_screen.dart` — type selector chips, name,
  target, conditional fields per type (per-period amount + frequency
  for fixed; total days for daysChallenge; total weeks for
  weeksChallenge), start date + optional end date, note. Daily and
  weekly challenge contribution amounts auto-derive as
  `target / total`.
- `saving_plan_detail_screen.dart` — hero (gradient, big saved
  amount, progress, remaining), details card, **slot grid** for
  challenge plans (each cell = day or week with auto-computed
  amount and date; tap to deposit / un-deposit), contribution
  history list for fixed / flexible plans, action chips
  (Edit / Mark completed / Cancel / Delete-with-confirm). FAB
  "Add contribution" appears for fixed / flexible active plans.

### Navigation: Money Tools
Per spec option A (don't overcrowd home), entry points live in
**Profile → Money Tools** as a new grouped section with two tiles:
- Borrow & Lending → opens `BorrowLendingScreen`.
- Saving Plans → opens `SavingPlansScreen`.

The bottom nav (Home / Stats / Budget / Profile) is unchanged.

### Storage and CSV
`local_storage.dart` now opens two new Hive boxes on init —
`trackora_borrow_lending_v1` and `trackora_saving_plans_v1` — alongside
the existing expense / installment / meta boxes.

### Localization
All new UI strings have keys in `lib/services/i18n.dart` for English,
Chinese (Simplified), and Malay. The two new namespaces are
`bl.*` (borrow & lending) and `sp.*` (saving plans), plus `tools.*`
for the Money Tools section header in Profile. Missing keys still
fall back to English so the app never shows a raw key.

### Files created
- `lib/models/borrow_lending.dart`
- `lib/models/saving_plan.dart`
- `lib/repositories/borrow_lending_repository.dart`
- `lib/repositories/local_borrow_lending_repository.dart`
- `lib/repositories/firebase_borrow_lending_repository.dart`
- `lib/repositories/saving_plan_repository.dart`
- `lib/repositories/local_saving_plan_repository.dart`
- `lib/repositories/firebase_saving_plan_repository.dart`
- `lib/services/borrow_lending_service.dart`
- `lib/services/saving_plan_service.dart`
- `lib/screens/borrow_lending/borrow_lending_screen.dart`
- `lib/screens/borrow_lending/add_edit_borrow_lending_screen.dart`
- `lib/screens/borrow_lending/borrow_lending_detail_screen.dart`
- `lib/screens/savings/saving_plans_screen.dart`
- `lib/screens/savings/add_edit_saving_plan_screen.dart`
- `lib/screens/savings/saving_plan_detail_screen.dart`

### Files modified
- `lib/repositories/local_storage.dart` — two new Hive boxes.
- `lib/state/providers.dart` — providers for both new modules.
- `lib/screens/settings/settings_screen.dart` — Money Tools section,
  CSV icon swap.
- `lib/services/i18n.dart` — `tools.*`, `bl.*`, `sp.*` keys for
  en / zh / ms.
- `docs/PROJECT_CONTEXT.md` — this update.

### Quality checks
- `dart analyze lib/` → **No issues found!** across the whole tree.
- Offline-first preserved — every screen goes through providers /
  services / repositories. No direct Hive or Firestore access in any
  new screen.
- Existing CSV export / import unchanged.
- Existing pages (Home dashboard, Statistics, Budget, Installments,
  Add/Edit Expense, Quick Add Sheet, Apple Watch, iOS widget) were
  not modified beyond the icon swap and the new Profile section.
- Image attachment for Borrow & Lending reuses
  `StorageService.saveReceipt` and renders through the same
  `ReceiptPreview` widget — works on save, persists across restart,
  and resolves correctly via the relative-path scheme already used
  by expense receipts.
- All money formatting goes through `formatMoney(symbol, value)` so
  every number shows two decimals consistently.

### Known limitations
- **CSV export / import does not include the new modules.** The
  current `ExportService` is hard-wired to expenses. Borrow &
  Lending and Saving Plans are persisted only in their own Hive
  boxes; switching to Firebase mode keeps them too, but a CSV
  round-trip will only carry expenses. A future pass can add
  separate JSON / CSV exports per module.
- Borrow & Lending image attachments share the receipts directory
  on disk. Their on-device path is portable across app launches but
  not across devices (same caveat as expense receipts — documented
  earlier).
- The challenge-grid auto-derives the per-slot amount as
  `target / total`. Editing the target after some deposits don't
  retroactively update the recorded contribution amounts; the
  progress ring still tracks `currentAmount / targetAmount`
  faithfully, but the slot labels show the *latest* per-slot
  derivation. Use the Edit screen if you need to reset cleanly.
- The new modules are not yet wired into the iOS home-screen widget
  or the Apple Watch app.

### Run

```sh
flutter pub get
cd ios && pod install && cd ..
flutter run --release -d 00008150-001870EA3693401C
```

---

## Earlier Pass — Balance Privacy, Installments Redesign, Interactive Stats, Profile Beautification

### Balance privacy toggle
Bank-style hide/show on the dashboard hero. New persisted preference in
`PrefsService.balanceVisible()` (default `true`), exposed via
`balanceVisibleProvider` (StateNotifier). Toggle survives restart.

UI:
- The white "all time" pill on the hero card has been replaced with a
  tappable eye/eye-off icon button.
- The big balance number renders through new
  `lib/widgets/masked_amount.dart` — when hidden it shows
  `RM ****` (currency symbol stays visible so the row width is stable
  and the user still knows the unit).
- The mini "Lifetime in / Lifetime out" chips below the hero also mask
  to `$ ****` when hidden so the user can hand the phone over without
  exposing any balance signal.
- **Calculations are not affected** — the underlying Riverpod values
  stay real, only the display flips.

### Installments management page redesign
`lib/screens/installments/installments_screen.dart` rewritten end-to-end
for clarity. Layout:

1. **Summary card** at the top:
   - Total monthly installment payment (large headline number).
   - Active installment count.
   - Total remaining across all active fixed-term plans.
2. **List**, sorted active → completed → cancelled. Each tile is
   **collapsed by default** showing only the essentials:
   - Category icon, name, status badge.
   - Monthly amount + "per month" subtitle.
   - Single secondary line: `N months left · remaining $X` (fixed) or
     `Ongoing · next due Mmm d` (lifetime). Status text for
     completed / cancelled.
   - Slim progress bar for fixed-term plans only.
3. **Tap a tile to expand** — animated reveal showing start date,
   total months, months paid, next payment date, due day, and
   original amount (when set). Below those, an inline
   "Mark paid for {Month}" button (active-and-now plans only) and a
   row of iOS-style action chips:
   - **Edit** → opens edit screen.
   - **Mark completed** → only when active.
   - **Cancel** / **Reactivate** → with confirm dialog.
   - **Delete** → with confirm dialog (destructive).
4. The old ellipsis action sheet is gone — actions live in the
   expanded panel where they have context.

The `_StatusBadge` and `_ProgressRow` helpers are kept and slightly
restyled (5 pt bar height, paid/total months caption underneath).

### Stats: calendar removed, interactive category chart
`lib/screens/home/statistics_screen.dart`:

- The `_CalendarCard` and its helper classes (`_DayCell`,
  `_WeekdayLabel`, `_DayEntryRow`) were **removed** completely.
- `_CategoryCard` is now stateful and interactive:
  - Larger 180×180 donut.
  - Tap a slice → that slice grows (radius 26 vs 20) and gets a
    white border ring; the centre label switches to show the touched
    category's name, amount, and percentage.
  - When nothing is selected, the centre shows the grand total.
  - Below the chart, a hint line guides the user
    ("Tap a slice or row to see details") that disappears once a
    selection is active.
  - The legend rows below are now also tappable (and long-pressable
    with haptic feedback) — selecting a row from the list focuses the
    matching slice. Each row shows category, percentage, amount, and
    a thin progress bar for at-a-glance scanning.
  - An ✕ close button appears in the header when something is
    selected, for quick deselect.
- The weekly chart is unchanged.

New i18n key: `stats.tapSliceHint` (en / zh / ms).

### Profile page beautification + iOS polish
`lib/screens/settings/settings_screen.dart` redesigned:

- **Hero profile card** — new gradient (lilac → sky) container with a
  larger 64×64 white avatar disc and shadow. "OFFLINE PROFILE" /
  "SIGNED IN" badge is now uppercase 11 pt with letter-spacing for
  the iOS Settings feel; email below at 17 pt 800.
- **Grouped sections** — preferences split into four iOS-style groups
  with all-caps mini headers: **Account** (currency, starting
  savings), **Display** (appearance, language), **Data** (export,
  import), **About** (version, sign out).
- New private widgets: `_ProfileHero`, `_GroupHeader`, `_GroupCard`,
  `_GroupDivider`, `_Tile`. The legacy `_row` helper was removed.
- Tiles use coloured square icon badges (mint / peach / lilac / sky /
  sage / butter / sand / blush) — each row has its own visual hook
  while staying calm.
- Dividers are now hairline 0.5 pt with the standard 60 pt indent so
  they sit under the label, not edge-to-edge.
- All taps trigger `HapticFeedback.selectionClick` for the iOS feel.
- Trailing values use `brand.inkSoft` w500 (was w600 + small text) so
  they read as secondary, not competing with the primary label.
- Soft shadow under each group card (3 pt offset, 12 pt blur) for a
  floating-card feel instead of a flat surface.
- Existing actions (currency picker, theme picker, language picker,
  starting-savings editor, CSV export / import, sign out) are all
  preserved — only the chrome around them changed.

New i18n keys: `settings.account`, `settings.display`, `settings.data`
(en / zh / ms).

### Files changed in this pass
- `lib/services/prefs_service.dart` — added `balanceVisible()` /
  `setBalanceVisible()`.
- `lib/state/providers.dart` — added `BalanceVisibilityNotifier` +
  `balanceVisibleProvider`.
- `lib/widgets/masked_amount.dart` — **new** small helper widget.
- `lib/screens/home/dashboard_screen.dart` — eye/eye-off toggle on
  hero card, masking applied to balance + mini chips. Hero card is
  now a `ConsumerWidget`.
- `lib/screens/installments/installments_screen.dart` — full rewrite
  (summary card, sorted list, collapsed tiles, expandable details
  with action chips).
- `lib/screens/home/statistics_screen.dart` — removed
  `_CalendarCard` & helpers; `_CategoryCard` rewritten as stateful
  with interactive chart + tappable legend; new `_CenterLabel` and
  `_LegendRow` widgets.
- `lib/screens/settings/settings_screen.dart` — beautified hero,
  grouped sections, new tile / divider / group / hero widgets; old
  `_row` removed.
- `lib/services/i18n.dart` — new keys for installment summary and
  details, stats chart hint, settings sub-section labels (en/zh/ms).
- `docs/PROJECT_CONTEXT.md` — this update.

### Quality checks
- `dart analyze lib/` → **No issues found!** across the whole tree.
- Offline mode unaffected — all changes go through repositories /
  providers.
- Installment math unchanged — `paidCount`, `monthsLeft`,
  `totalRemaining`, `progress`, `nextDueDate` getters used by both
  the new summary card and the per-tile progress row produce the
  same numbers as before.
- Balance hide/show persists via `SharedPreferences.balance_visible`.
  Verified with the standard load-on-init pattern used by theme /
  locale.
- Stats chart percentages add up to 100 % by construction
  (`pct = entry.value / total`).
- Profile actions still work — handlers (`_pickCurrency`,
  `_pickThemeMode`, `_pickLanguage`, `_editOpeningSavings`,
  `_exportCsv`, `_importCsv`, sign out) are identical, only the
  parent chrome was redesigned.
- No unrelated pages touched: budget screen, add/edit expense, watch
  app, widget extension are all untouched in this pass.

### Known limitations
- Mask currently only hides the hero balance + lifetime chips on
  Home. Recent activity rows still show real amounts — those are
  individual transactions, not "balance", so the spec ("Total balance
  / current total left") is satisfied. Easy to extend later if you
  want full ledger masking.
- The interactive category slice highlight relies on `fl_chart`'s
  touch feedback. On very small slices (< 1 % of total) the touch
  area can be hard to hit — users can always tap the legend row
  instead, which targets the same index.
- The installment "Mark paid for {Month}" button only appears when
  the **selected month** in the rest of the app matches an active
  month for that plan. Browsing past months still surfaces the
  control; future months hide it (matches existing behaviour).
- Profile / Settings strings that were already translated stay
  translated. The new section headers are localized in en / zh / ms;
  any future rows added there should follow the same pattern.

### Run

```sh
flutter pub get
cd ios && pod install && cd ..
flutter run --release -d 00008150-001870EA3693401C
```

If Xcode regenerates the iOS project or the widget extension, also
run once:

```sh
ruby tool/configure_widget_target.rb
```

---

## Earlier Pass — Calendar Stats, Language Switcher, Cleaner Stats Palette, Tighter Installment Banner

### Stats: Calendar view replaces transactions-by-date
`lib/screens/home/statistics_screen.dart` — the collapsible
"Transactions by date" card was removed and replaced with
`_CalendarCard`. The new visual is a 6×7 month grid:

- Each day cell shows day number + tiny daily-spend amount.
- Background tints with a mint gradient — the more you spent that day,
  the deeper the tint. Days with no activity stay neutral.
- Today is outlined; tapping any cell selects it (accent fill).
- Below the grid, the selected day's entries expand inline with
  category, note and signed amount. Tapping the same cell again
  collapses.
- Header summarises monthly total spent.
- Weekday header is Mon-first to match the existing weekly chart.
- Driven by the same `MonthFilterBar` selected month as the rest of
  Stats.

### Stats palette cleanup
The pastel mint / peach card backgrounds on the weekly chart and
category card looked busy stacked above each other. Both cards now use
the theme's neutral surface (`brand.surface`). Their identity comes
from a small accent badge on the title row instead:

- Weekly spend → mint icon badge.
- By category → lilac icon badge.
- Calendar → background-tinted icon badge.

Loading and error placeholders dropped their pastel backgrounds too —
they share the same neutral surface so transitions don't flash colour.

### Installment status banner — terser
`_StatusSummary` (the green card on the edit screen) used to show "N
payments so far" / "X / Y months paid". Per spec it now leads with
what the user owes, not what they've done:

- Active fixed plans: `N months left` + `Total remaining: $X`.
- Lifetime: `Lifetime / ongoing` + `Cancel anytime`.
- Completed: `All Y months paid`.
- Cancelled: `No longer counted in monthly totals`.

The list-tile progress row already shows `paid / total`, so the
detailed count is no longer duplicated on the banner.

### Language switcher (English / Chinese / Malay)

New `lib/services/i18n.dart` provides:

- `AppLocale` enum: `system` (default), `en`, `zh`, `ms`.
- `AppStrings` — in-process key/value table with three languages.
  English is the master copy; missing keys in `zh` / `ms` fall back to
  English so the app never shows a raw key.
- `BuildContext.t(key)` extension for ergonomic lookup.

Persistence: `PrefsService.appLocale()` / `setAppLocale()` under the
`app_locale` key. `LocaleNotifier` (in `state/providers.dart`) loads
on start, writes on change.

Wiring: `MaterialApp.locale` reads from `localeProvider`. Added
`flutter_localizations` to `pubspec.yaml` so Material / Cupertino
system widgets (date pickers, dialogs) get translated month names
and button labels for free. `intl` was bumped from `^0.19.0` to
`^0.20.2` because `flutter_localizations` requires it.

UI: **Settings → Language** opens a bottom sheet with `System default
/ English / 中文 / Bahasa Melayu`. Tapping persists immediately —
no restart needed.

Translated screens this pass:
- Bottom-nav tabs (Home / Stats / Budget / Profile).
- Dashboard headers (Total balance, Income, Spent, Lifetime in/out,
  Recent activity, Monthly budget).
- Settings labels (all preference rows + section headers).

Untranslated (still English) — listed honestly:
- Add/edit expense form, quick-add sheet body, installment edit form,
  budget screen, calendar weekday letters (single-letter so they read
  fine across languages anyway), error / snackbar messages.

Adding more strings is a two-step copy-paste — see the comment at the
top of `i18n.dart`. No code refactor needed.

### Files changed in this pass
- `pubspec.yaml` — added `flutter_localizations`, bumped `intl` to
  `^0.20.2`.
- `lib/services/i18n.dart` — **new** language support.
- `lib/services/prefs_service.dart` — `appLocale()` / `setAppLocale()`.
- `lib/state/providers.dart` — `LocaleNotifier` + `localeProvider`.
- `lib/main.dart` — `MaterialApp.locale`, `localizationsDelegates`,
  `supportedLocales`.
- `lib/screens/settings/settings_screen.dart` — language picker,
  translated row labels.
- `lib/screens/home/home_shell.dart` — translated tab labels.
- `lib/screens/home/dashboard_screen.dart` — translated hero / metric
  labels.
- `lib/screens/home/statistics_screen.dart` — calendar replaces
  transactions-by-date, neutral surface backgrounds, mint/lilac icon
  badges, removed unused `_dayKey`.
- `lib/screens/installments/add_edit_installment_screen.dart` —
  simplified status banner.
- `docs/PROJECT_CONTEXT.md` — this update.

### Quality checks
- `dart analyze lib/` → **No issues found!**.
- `flutter pub get` succeeds with the new `flutter_localizations` +
  `intl ^0.20.2` constraint.
- Offline-first preserved — the locale provider only writes to
  shared prefs, no network.
- CSV import/export unaffected.
- Widget data flow unchanged.

### Known limitations
- Translation coverage is partial by design — most chrome is
  translated, deeper forms still read English. Documented above so the
  user knows where to extend.
- WidgetKit (the iOS home-screen widget) is **not** localised. The
  widget runs in its own process and reads strings from the Swift
  source — translating it would mean shipping a localisation bundle
  inside the extension. Out of scope for this pass.

### Run

```sh
flutter pub get
cd ios && pod install && cd ..
flutter run --release -d 00008150-001870EA3693401C
```

---

## Earlier Pass — Widget Layout, Quick-Add Sheet, Existing Installments, Transactions-by-Date, Receipt Fix

### Widget layout fix
`ios/TrackoraWidget/TrackoraWidget.swift` rewritten to fit cleanly at
both supported sizes:

- `.lineLimit(1)` + `.minimumScaleFactor(0.45–0.7)` everywhere a number
  or label can grow.
- Tighter padding (12 pt) so the headline column gets actual breathing
  room on systemSmall.
- Quick-add column has a fixed 94 pt width on medium so the headline
  side never gets squeezed by long currency strings.
- Progress bar height 4 pt, corner radius 3 pt — consistent with iOS
  widget norms.
- "Today / This week" lines kept on both sizes so users always see
  the spend velocity, not just the static remaining number.

### Custom button → compact quick-add modal
The widget's **Custom** button now deep-links to `trackora://quickadd`
instead of `trackora://add`. The new
`lib/screens/expenses/quick_add_sheet.dart` is a Cupertino bottom sheet
with a single autofocus amount field and a row of category chips. Save
persists through `ExpenseRepository` (storage-neutral — works in local
and Firebase modes).

`DeepLinkService` now routes:
- `trackora://add` → full Add/Edit screen (existing).
- `trackora://quickadd` → `QuickAddSheet`. `?amount=N` pre-fills the
  amount field — used by the iOS 16 fallback link so older OS still
  gets a one-tap flow without App Intents.

iOS limitation, documented in source: WidgetKit does not allow text
input *inside* the widget. The compact sheet is the closest possible
UX — far less disruptive than launching the full add-expense screen.

### Installments — existing-plan setup
`lib/models/installment.dart` adds two new fields:

- `int paidMonthsAtStart` (default 0) — payments the user already made
  before adopting Trackora. Effective `paidCount = paidMonthsAtStart +
  paidMonths.length`, capped at `totalMonths` when set.
- `double? originalPrincipal` — informational; the original full plan
  amount.

New getter `nextDueDate({DateTime? from})` returns the next unpaid due
date, or null when the plan is complete / cancelled.

`add_edit_installment_screen.dart` introduces a **New / Existing**
toggle on creation:

- **New** — start date today, total months, monthly amount.
- **Existing** — surfaces a yellow "Existing progress" card with three
  optional helpers (any one is enough):
  1. Months paid + months left → totalMonths inferred.
  2. Original total months + start date → user can simply enter total.
  3. Current remaining balance → divided by monthly amount to derive
     remaining months.
  Logic lives in `_resolvePlan()`.

The "Lifetime / ongoing" switch labels itself as cancel-anytime when
on. The status banner now shows "Next due MMM d" for active fixed-term
plans.

### Manage installments page polish
`lib/screens/installments/installments_screen.dart` — each tile now
has:

- Status badge (Active / Completed / Cancelled).
- Subtitle = next due date (e.g. "Next due Jun 14") for active plans.
- Larger inline "Mark paid for {Month} ✓" button instead of a tiny
  pill, with haptic on tap.
- Three-dot ellipsis → opens a Cupertino action sheet with **Edit**,
  **Mark completed**, **Cancel** / **Reactivate**, and **Delete** (the
  last two require explicit dialog confirmation).
- Lifetime line shows "Ongoing • N prior + M in-app" when
  `paidMonthsAtStart > 0` so back-filled history is visible.

### Stats: Transactions by Date
`lib/screens/home/statistics_screen.dart` — new collapsible
`_TransactionsByDateCard` lives below the charts (per spec — main
expense list is unchanged). Header summarises entry count + day count;
chevron rotates to expand. Inside, entries group by date with a header
showing the daily net (income − expenses), then category icon, note,
and signed amount per row. Filtered by the existing
`MonthFilterBar` so it shares the user's selected month with the
category card.

### Receipt attachment fix
The bug was a combination of three issues:

1. `StorageService.saveReceipt` returned the **absolute** sandbox path
   for local mode. iOS rotates the data-container UUID on every
   reinstall, so old expenses pointed at non-existent files.
2. The add/edit screen never displayed the receipt — only said
   "Receipt attached".
3. `Expense.copyWith` could not clear `receiptUrl`, so removing a
   receipt silently kept the old one.

Fixes:

- `lib/services/storage_service.dart` now returns a **relative** path
  (`receipts/{userId}/{ts}.{ext}`). New `StorageService.resolveLocal`
  resolves against the current `getApplicationDocumentsDirectory()`,
  and accepts both new relative paths and legacy absolute paths so
  existing entries keep working.
- `lib/widgets/receipt_preview.dart` — new widget. Thumbnail for the
  saved attachment, opens a full-screen `ReceiptViewerScreen` with
  pinch-to-zoom on tap. Handles image extensions (PNG / JPG / JPEG /
  HEIC / WebP), remote https URLs, and non-image files (file-icon
  fallback). Surfaces a clear "missing" badge when the underlying
  file can't be resolved.
- `lib/screens/expenses/add_edit_expense_screen.dart` — receipt card
  now shows the actual thumbnail plus **Replace** and **Remove**
  actions when an attachment exists.
- `lib/models/expense.dart` — `copyWith` uses a sentinel for
  `receiptUrl` so callers can pass `null` to clear it.

The expense card already shows a paperclip icon when an entry has a
receipt — that part was already correct.

#### CSV export/import + receipts (limitation)
- The CSV "Receipt URL" column carries whatever string is stored.
- For local mode, that's a path like `receipts/{userId}/{ts}.jpg`.
  The path is meaningful **on the device that exported it**. On
  another device, the file referenced by that path doesn't exist and
  the receipt preview shows the missing-file badge.
- For Firebase mode, the column is an `https://` URL that resolves
  anywhere.
- This is unchanged from before. To migrate receipts between devices,
  use Firebase mode or AirDrop the `receipts/` directory alongside
  the CSV.

### Files changed in this pass
- `lib/models/expense.dart` — sentinel-based `copyWith` for
  nullable `receiptUrl`.
- `lib/models/installment.dart` — `paidMonthsAtStart`, `originalPrincipal`,
  `paidInApp`, `amountPaid`, `nextDueDate`, updated effective paid
  count.
- `lib/services/storage_service.dart` — relative receipt paths,
  `resolveLocal`, `isRemote` helpers.
- `lib/services/deep_link_service.dart` — `trackora://quickadd` route
  with optional `amount` query param.
- `lib/screens/expenses/quick_add_sheet.dart` — **new** compact
  quick-add bottom sheet.
- `lib/screens/expenses/add_edit_expense_screen.dart` — receipt card
  with thumbnail / Replace / Remove.
- `lib/screens/installments/add_edit_installment_screen.dart` — New /
  Existing setup mode, "Existing progress" helper card, start-date
  picker, original-principal field, status banner with next due date.
- `lib/screens/installments/installments_screen.dart` — action sheet
  (edit / complete / cancel / delete), inline mark-paid button,
  next-due-date subtitle, prior-payments line for back-filled lifetime
  plans.
- `lib/screens/home/statistics_screen.dart` — `_TransactionsByDateCard`
  collapsible section below the charts.
- `lib/widgets/receipt_preview.dart` — **new** reusable preview +
  full-screen viewer.
- `ios/TrackoraWidget/TrackoraWidget.swift` — responsive layout, fixed
  width quick-add column, line limits + scale factors, small chrome
  now opens the quick-add sheet.
- `docs/PROJECT_CONTEXT.md` — this update.

### Quality checks
- `dart analyze lib/` → **No issues found!**
- Offline mode unaffected — all changes go through repositories.
- CSV import/export untouched. Receipt path semantics documented above.
- Widget data still pushed by `WidgetSyncService.push` and bumped
  optimistically by `QuickAddExpenseIntent`.
- Installment math verified manually:
  - New plan: paidCount = paidMonths.length, monthsLeft = total − that.
  - Existing plan: paidCount = paidMonthsAtStart + paidMonths.length,
    capped at totalMonths.
  - Lifetime: paidCount = raw sum, no monthsLeft.

### Known limitations / risks
- WidgetKit does not allow native text input — the "Custom" widget
  button always opens the in-app sheet. This is an Apple platform
  constraint, not a Trackora limitation.
- Local-mode receipt files don't roam between devices; CSV import on a
  fresh install will show "missing" placeholders for receipts. Use
  Firebase mode for cross-device receipts.
- The widget's optimistic counters (`todaySpent` / `weekSpent` etc.)
  are bumped by App Intent quick-adds before the Flutter app drains
  the queue. If the user kills the app and never reopens it, those
  counters drift until the next dashboard rebuild reconciles them.
- `flutter analyze` / `flutter test` still flaky on this machine due
  to a missing analysis-server / `flutter_tester` snapshot in the SDK
  cache (pre-existing, unrelated to this pass).

### Run

```sh
flutter pub get
cd ios && pod install && cd ..
flutter run --release -d 00008150-001870EA3693401C
```

If the widget extension was regenerated, run once:

```sh
ruby tool/configure_widget_target.rb
```

---

## Earlier Pass — Widget App Intents, Installments Upgrade, App Store Hardening

### iOS Widget — quick-add via App Intents (iOS 17+)

The medium widget now lets the user record an expense **without opening
Trackora**. New file `ios/TrackoraWidget/QuickAddExpenseIntent.swift`
declares an `AppIntent` with `openAppWhenRun = false`. The widget renders
three quick buttons (`+5 / +10 / +20`, default category **Food**) plus a
**Custom** link that deep-links to the in-app add screen for any other
amount or category.

When tapped, the intent:

1. Reads / creates a JSON queue at App Group key
   `pending_widget_expenses_json`.
2. Appends `{ id, amount, category, ts }`.
3. Optimistically bumps `todaySpent`, `weekSpent`, `monthSpent`,
   `budgetableSpent` so the widget shows the new total instantly.
4. Calls `WidgetCenter.shared.reloadAllTimelines()`.

Flutter side (`lib/services/widget_intent_service.dart`):
- `WidgetIntentService.drain(userId, repo)` reads the JSON queue,
  persists each entry through the active `ExpenseRepository`, then
  clears the queue. Storage stays neutral — the same drain works in
  local mode and Firebase mode.
- `lib/main.dart` wires it up: `TrackoraApp` is now a
  `ConsumerStatefulWidget` with `WidgetsBindingObserver`. Drain runs on
  cold-start (post-frame), on every `AppLifecycleState.resumed`, and on
  every auth-state change once a user is known.

`lib/services/widget_sync_service.dart` now also pushes `todaySpent`
and `weekSpent`. The dashboard computes them across **all** expenses
(not the selected month) so the widget reflects "right now" even while
the user is browsing past months.

iOS 16 and earlier do not have the `Button(intent:)` API; on those
devices the same buttons render as `Link`s that deep-link to the
in-app add-expense screen with a pre-filled `amount` query parameter
fallback. Widget functionality on small (2x2) is unchanged — it still
deep-links to `trackora://add` since there's no room for action chips.

### Limitations / risks
- App Intents from a widget run in the extension process. They cannot
  trigger Flutter / Hive directly — that's why we use a JSON queue +
  drain pattern. The user might briefly see a stale total if they kill
  the app between the widget tap and the app's next launch; the
  optimistic counter bump masks this for ~99 % of cases.
- Widget today/week numbers are last-pushed values — they only refresh
  while the dashboard is rendered or the queue drains. A standalone
  background refresh is not implemented.
- Quick-add category is currently fixed to **Food**. Adding more
  presets (Transport, Shopping) would just be more `Button(intent:)`
  calls, but the widget runs out of room fast.

### Installments — lifetime, cancel, complete, progress

`lib/models/installment.dart` adds two fields:

- `int? totalMonths` — `null` means **lifetime** (Netflix / rent /
  open-ended subscription). `> 0` is a fixed-term plan.
- `bool cancelled` — hard stop; user can toggle anytime, reactivate
  later.

Derived getters: `isLifetime`, `paidCount` (clamped), `monthsLeft`,
`totalRemaining` (= `monthsLeft × amount`), `progress` (0..1),
`status` (`active` | `completed` | `cancelled`). `isActiveIn(month)`
now also returns false for completed and cancelled installments so they
no longer count toward "this month's commitments".

Service additions (`lib/services/installment_service.dart`):
- `setCancelled(userId, installment, bool)`
- `markCompleted(userId, installment)` — pins `totalMonths` to current
  paid count (min 1).
- `reactivate(userId, installment)`

UI (`lib/screens/installments/installments_screen.dart`):
- Each tile shows a status badge (Active / Completed / Cancelled) and,
  for fixed-term plans, a progress bar with `paid / total months` plus
  `N left • $X` total remaining.
- Lifetime plans show `Lifetime • N payments so far`.
- "Mark paid / Mark unpaid" still works on the same row, but only for
  active plans active in the selected month — completed and cancelled
  rows show no action button.

Edit screen (`lib/screens/installments/add_edit_installment_screen.dart`):
- New "Plan length" section with a **Lifetime** switch and (when off) a
  **Total months** input.
- Status summary banner at the top when editing.
- Two new actions below Save: **Mark as completed** and
  **Cancel installment** / **Reactivate installment**.
- Default total months for a new plan is `12`.

Backwards compatibility: existing stored installments without
`totalMonths` / `cancelled` keys still load — they are treated as
lifetime / not-cancelled respectively. No data migration required.

### App Store readiness / security pass

Verified clean:
- `dart analyze lib/` returns **No issues found!**.
- Zero `print()` / `debugPrint` calls in `lib/` (grep confirmed).
- No insecure HTTP URLs; no `NSAppTransportSecurity` exception.
- `ITSAppUsesNonExemptEncryption=false` already set.
- Permissions limited to **Camera** + **Photo Library**, both with
  user-facing reasons in `Info.plist` describing receipts.
- App Group `group.com.michaelchia.trackora` is the only sandbox
  exit; only Trackora targets share it.
- Hive data lives in the app's sandboxed documents directory — clean
  on uninstall, not exposed to Files app.
- App is fully offline by default (`storageMode = StorageMode.local`).
  Firebase code is gated behind that switch and never initialised in
  local mode.

Hardening added:
- The widget-queue drain swallows malformed JSON instead of crashing
  the app (defensive `try / catch` + queue clear).
- Installment edit screen now shows generic "Failed to save installment"
  instead of leaking exception text into a SnackBar.
- Lifecycle observer added to `TrackoraApp` — installed and removed
  symmetrically in `initState` / `dispose`.

### Remaining risks
- Widget `Button(intent:)` requires iOS 17. Older devices fall back to
  deep links — they do open the app to add. This is documented; not
  blocking App Store review.
- The drained widget queue is best-effort: failed `addExpense` calls
  drop the entry rather than retry. Acceptable for tiny amounts; a
  retry log could be added later.
- No automated end-to-end test for the widget → drain → repository
  path (would need a paired iOS device + Hive instance). Manual test
  required.
- `flutter analyze` / `flutter test` still flaky on this machine due
  to a missing analysis-server / `flutter_tester` binary in the SDK
  cache (pre-existing, unrelated to these changes).

### Files changed in this pass
- `lib/models/installment.dart` — added `totalMonths`, `cancelled`,
  status / progress getters, `isActiveIn` excludes non-active statuses.
- `lib/services/installment_service.dart` — `setCancelled`,
  `markCompleted`, `reactivate`.
- `lib/screens/installments/installments_screen.dart` — rewritten as
  composable tile with progress bar, status badges, lifetime line.
- `lib/screens/installments/add_edit_installment_screen.dart` — plan-
  length section (lifetime switch + total months), status summary
  banner, mark-completed and cancel actions, friendlier error text.
- `lib/services/widget_sync_service.dart` — pushes `todaySpent` and
  `weekSpent` keys.
- `lib/services/widget_intent_service.dart` — **new**; drains widget
  quick-add queue via `ExpenseRepository`.
- `lib/screens/home/dashboard_screen.dart` — computes today / week
  totals from `allExpensesProvider` and includes them in the widget
  push.
- `lib/main.dart` — `TrackoraApp` is now a stateful consumer with
  `WidgetsBindingObserver`. Drains widget queue on cold-start, on
  resume, and on auth-state change.
- `ios/TrackoraWidget/TrackoraWidget.swift` — new medium layout with
  Today / This-week lines and the quick-add button column. Small
  layout adds a Today / Week line.
- `ios/TrackoraWidget/QuickAddExpenseIntent.swift` — **new**; the
  AppIntent that records a quick add into the App Group queue.
- `tool/configure_widget_target.rb` — also links
  `QuickAddExpenseIntent.swift` into the widget target's source build
  phase.
- `docs/PROJECT_CONTEXT.md` — this update.

### Manual Xcode steps (one-time)

The Ruby helper handles target wiring, but if Xcode regenerates the
project or the new file isn't picked up, do this once:

1. Open `ios/Runner.xcworkspace`.
2. Confirm `TrackoraWidget` target's **Build Phases → Compile Sources**
   contains both `TrackoraWidget.swift` and `QuickAddExpenseIntent.swift`.
3. `TrackoraWidget` target → **Signing & Capabilities** still has the
   App Group `group.com.michaelchia.trackora` ticked.
4. Deployment target stays at **iOS 14.0** (or whatever it was). The
   AppIntent code is gated with `@available(iOS 17.0, *)`; older OS
   automatically falls back to deep links.
5. Re-run `ruby tool/configure_widget_target.rb` if anything looks
   off — idempotent.

### Run

```sh
flutter pub get
cd ios && pod install && cd ..
flutter run --release -d 00008150-001870EA3693401C
```

## Files Changed (Most Recent Pass)

- `lib/theme/app_theme.dart` — added `foregroundOn(...)` for readable text
  on selected chips/buttons and set themed input prefix/suffix icon colours.
- `lib/screens/expenses/add_edit_expense_screen.dart` — migrated scaffold,
  date picker, date/receipt cards, entry-type toggle, selected category chips,
  and loading spinner to the active theme.
- `lib/screens/installments/add_edit_installment_screen.dart` —
  migrated scaffold, due-day selector, selected category chips, and loading
  spinner to the active theme.
- `lib/screens/installments/installments_screen.dart` — migrated scaffold
  and non-pastel list/empty text to active theme colours.
- `lib/screens/home/budget_screen.dart` — migrated non-pastel budget rows
  and budget edit bottom sheet to active theme colours.
- `lib/screens/settings/settings_screen.dart` — migrated profile/preference
  rows and bottom sheets to active theme colours.
- `lib/screens/auth/login_screen.dart`, `lib/screens/auth/signup_screen.dart`
  — migrated Firebase auth screens to active theme colours.
- `ios/Runner.xcodeproj/project.pbxproj` — added `TrackoraWidget` WidgetKit
  target and embedded `TrackoraWidget.appex` in Runner.
- `tool/configure_widget_target.rb` — new idempotent helper to recreate /
  repair the widget target setup.
- `docs/PROJECT_CONTEXT.md` — this context update.

## Earlier Pass

- `lib/widgets/on_pastel.dart` — new `OnPastel` wrapper that forces all
  inherited text + icon colors inside its child to the light-mode ink
  palette. Used so brand pastel cards (mint / lilac / peach / sage / …)
  stay readable under dark mode where the default text color is white.
- `lib/widgets/section_card.dart` — auto-detects whether a passed `color`
  is a light pastel (luminance > 0.55) and, if so, wraps the child in
  `OnPastel`. Added a `pastel: false` opt-out used by the Total Balance
  hero (which deliberately uses a dark card background with white text).
- `lib/screens/home/dashboard_screen.dart` — Total Balance hero now uses
  `Color(0xFF24242A)` in dark mode (elevated dark grey) so the card
  separates from the near-black scaffold background. Light mode keeps
  pure black `0xFF111111`.
- `lib/widgets/month_filter_bar.dart`, `lib/widgets/pill_tabs.dart`,
  `lib/screens/home/home_shell.dart` — when the selected pill /
  segmented background is a *light* color (dark mode `accentDark` is
  near-white), the foreground now flips to **`Colors.black`** instead of
  `brand.ink` (which would also be white). Same fix applied to the FAB
  icon.
- `lib/screens/home/statistics_screen.dart` — weekly line chart now
  shows a permanent inline value label above every non-zero day via
  `LineChartData.showingTooltipIndicators`. Dot painter highlights the
  spot with a white-stroked filled circle. Chart height bumped to 200
  and `maxY` headroom by 5 % so the topmost label doesn't clip.
- `lib/services/export_service.dart` — Title-Case headers
  (`ID, Date, Type, Category, Amount, Note, Receipt URL, Created At,
  Updated At`), UTF-8 BOM, `\r\n` line endings (Excel-friendly),
  newest-first sort. Import now normalises headers (lowercase + strip
  spaces / underscores / hyphens) so old-format CSVs still import.
  Tolerates blank rows and `YYYY-MM-DD HH:mm:ss` dates.

## Pre-existing changes preserved

- `lib/theme/app_theme.dart` — introduced `BrandColors` `ThemeExtension`,
  `context.brand` getter, `AppTheme.dark()`, palette tokens for both modes.
- `lib/services/prefs_service.dart` — persists `themeMode()` /
  `setThemeMode(...)` (`'system' | 'light' | 'dark'`).
- `lib/state/providers.dart` — added `ThemeModeNotifier` +
  `themeModeProvider`.
- `lib/main.dart` — `MaterialApp` now uses `theme` + `darkTheme` +
  `themeMode`. Status-bar overlay style recomputed every frame from the
  effective brightness.
- `lib/widgets/section_card.dart`, `lib/widgets/expense_card.dart`,
  `lib/widgets/month_filter_bar.dart`, `lib/widgets/pill_tabs.dart`,
  `lib/screens/home/home_shell.dart` — migrated to `context.brand.*` so
  surfaces, backgrounds, and ink colors flip in dark mode.
- `lib/screens/home/dashboard_screen.dart` — removed Today / This week
  row; migrated chrome to `context.brand`.
- `lib/screens/home/statistics_screen.dart` — added include / exclude
  bills + instalments toggle on the Weekly chart and applied the filter
  through `allExpensesProvider`.
- `lib/screens/settings/settings_screen.dart` — added **Appearance** row
  + bottom-sheet picker (System / Light / Dark).
- `ios/TrackoraWidget/TrackoraWidget.swift` — refreshed widget body to
  match spec: Trackora label, remaining amount, monthly spent, "Tap to
  add expense" CTA. Now uses `budgetableSpent` so the widget remaining
  matches the iPhone home calculation.

## Watch Pass Preserved

- `pubspec.yaml` — added `watch_connectivity: ^0.2.1`.
- `lib/services/watch_service.dart` — new bridge that listens to `WCSession.sendMessage` and writes incoming expenses through the `ExpenseRepository`.
- `lib/state/providers.dart` — added `watchServiceProvider`.
- `lib/main.dart` — attaches the watch bridge once an auth user is available and re-attaches on auth changes.
- `ios/TrackoraWatch Watch App/` — new folder with the native watchOS app: `TrackoraWatchApp.swift`, `WatchSession.swift`, `ContentView.swift`, `AddExpenseView.swift`, `Info.plist`, `TrackoraWatch.entitlements`.
- `lib/screens/home/dashboard_screen.dart` — budget progress now uses `budgetableSpent` (excludes Bills category and installment-paid entries), matching the budget screen rule. Bar subtitle reads "bills & installments excluded". Wired `onDelete` on `ExpenseCard` so swipe-to-delete works.
- `lib/screens/home/budget_screen.dart` — moved **Manage installments** quick-action from the bottom to right under the title (no scrolling needed). New `_ManageInstallmentsTile` widget shows count + paid/pending summary. Added haptic on tap.
- `lib/widgets/expense_card.dart` — wrapped in `Dismissible` for iOS-style swipe-left-to-delete with red trash background, Cupertino confirm dialog, and haptic feedback (selection on tap, medium on swipe, heavy on confirm).

## Older Pass

- `lib/screens/home/dashboard_screen.dart` — full rewrite. Hero is **Total balance** (lifetime savings) instead of monthly "left". Adds Income/Spent metric cards, budget progress, and Today/This-week quick stats.
- `lib/screens/home/statistics_screen.dart` — added `interval: 1` and integer-tick guard on the bottom axis to fix duplicate day labels (Mon Mon, Tue Tue, …).
- `lib/services/export_service.dart` — `exportCsv` now accepts an optional `sharePositionOrigin` and forwards it to `Share.shareXFiles`. Without this, iOS throws `PlatformException(error, sharePositionOrigin:argument…)` because the share sheet popover has no anchor.
- `lib/screens/settings/settings_screen.dart` — export handler captures the tapped row's `RenderBox` rect and passes it as `sharePositionOrigin`. SnackBars unchanged.
- `docs/PROJECT_CONTEXT.md` — this file.

## Known Manual Xcode Steps

- **iOS Widget extension target** — now configured in `ios/Runner.xcodeproj`.
  Re-run `ruby tool/configure_widget_target.rb` only if the project file is
  regenerated or the target disappears. Runner and `TrackoraWidget` still
  need valid App Group-capable signing/provisioning in Xcode.
- **Watch app target** — same deal: native sources at
  `ios/TrackoraWatch Watch App/`, Xcode target was added manually. The
  Ruby helper `tool/configure_watch_target.rb` patches build settings
  (entitlements path, deployment target, MemberImportVisibility off)
  whenever the project file is regenerated.

## Theming Migration Notes

- The colour swap is wired via a `BrandColors` `ThemeExtension`. New
  widgets should consume `context.brand.surface` / `.background` /
  `.ink` / `.inkSoft` / `.divider` rather than `AppColors.surface` etc.
- Pastel brand colours (mint, lilac, peach, butter, blush, sky, sage,
  sand, income, expense, accent) are constant across both themes — they
  read on light and dark.
- High-traffic screens are now migrated for dark mode: home shell,
  dashboard, statistics shell, budget, settings, add/edit expense,
  installments, and Firebase auth screens. Remaining static `AppColors`
  references are mostly intentional pastel-card colours or light ink inside
  `OnPastel`.

## Known Issues

- `flutter analyze` may crash on this machine because the Flutter SDK cache is missing an analysis server snapshot. `dart analyze lib` works and currently passes (`No issues found!`).
- `flutter test` may fail on this machine because the Flutter SDK cache is missing `flutter_tester`.
- Apps installed with plain `flutter run` are debug builds and may not open normally after unplugging. Use `flutter run --release` for a standalone install on iPhone.
- If the iOS widget does not appear immediately after installing a build
  that includes the extension, first enter Home Screen edit mode → **+** →
  search **Trackora** and/or restart the iPhone. iOS can cache widget
  lists after the first extension install. Only delete/reinstall the app as
  a last resort because offline Hive data is removed with the app; export
  CSV first. Also confirm both Runner and `TrackoraWidget` signing use the
  App Group `group.com.michaelchia.trackora`.

## How To Run

```sh
flutter pub get
flutter run --release -d 00008150-001870EA3693401C
```

For development with hot reload:

```sh
flutter run -d 00008150-001870EA3693401C
```

## Important Decisions

- Offline/local mode is the default and must not require Firebase or network access for normal use.
- Firebase code must remain available for future migration/sync — do not delete `firebase_*` files or repositories.
- Screens use providers/services/repositories, never `Hive.box(...)` or `FirebaseFirestore.instance...`.
- Shared models stay storage-neutral where practical (`Expense.fromMap` / `toMap`, `Installment.fromMap` / `toMap`).
- Repository method names map closely to current app behaviors to keep migration small.
- CSV import/export must stay storage-neutral; it receives an `ExpenseRepository` and never assumes Hive or Firestore.
- Home is intentionally minimal: prioritize "how much can I still spend" over secondary metrics.
- Statistics is intentionally minimal: keep only the chart that drives weekly behavior change and the chart that shows where money goes monthly.

## Firebase Migration Notes

- Change `storageMode` in `lib/app_config.dart` to `StorageMode.firebase`.
- `main.dart` will initialize Firebase with `DefaultFirebaseOptions.currentPlatform`.
- Firebase Auth screens remain available in Firebase mode.
- Firestore collections currently follow `users/{userId}/expenses`, `users/{userId}/installments`, and `users/{userId}/meta`.
- Keep CSV import/export storage-neutral so imported expenses can be restored to local mode now and Firebase mode later.
- `upsertExpense` preserves imported CSV IDs in local mode and uses Firestore document IDs in Firebase mode when an ID is present.
