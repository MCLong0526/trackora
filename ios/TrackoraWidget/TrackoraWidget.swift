import WidgetKit
import SwiftUI

// MARK: - Data

struct TrackoraEntry: TimelineEntry {
    let date: Date
    let currency: String
    let monthSpent: Double
    let monthBudget: Double
    let savings: Double
    let upcoming: Double
    let budgetableSpent: Double
    let todaySpent: Double
    let weekSpent: Double
    let localeCode: String
    let draftAmount: Double
}

struct Provider: TimelineProvider {
    private let appGroup = "group.com.michaelchia.trackora"

    func placeholder(in context: Context) -> TrackoraEntry {
        TrackoraEntry(
            date: Date(),
            currency: "$",
            monthSpent: 0,
            monthBudget: 0,
            savings: 0,
            upcoming: 0,
            budgetableSpent: 0,
            todaySpent: 0,
            weekSpent: 0,
            localeCode: Locale.current.languageCode ?? "en",
            draftAmount: 10
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TrackoraEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrackoraEntry>) -> Void) {
        let entry = load()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> TrackoraEntry {
        let d = UserDefaults(suiteName: appGroup)
        let monthSpent = d?.double(forKey: "monthSpent") ?? 0
        let bsRaw = d?.double(forKey: "budgetableSpent") ?? 0
        let bs = bsRaw > 0 ? bsRaw : monthSpent
        let rawDraftAmount = d?.double(forKey: "widgetDraftAmount") ?? 10
        return TrackoraEntry(
            date: Date(),
            currency: d?.string(forKey: "currency") ?? "$",
            monthSpent: monthSpent,
            monthBudget: d?.double(forKey: "monthBudget") ?? 0,
            savings: d?.double(forKey: "savings") ?? 0,
            upcoming: d?.double(forKey: "upcomingInstallments") ?? 0,
            budgetableSpent: bs,
            todaySpent: d?.double(forKey: "todaySpent") ?? 0,
            weekSpent: d?.double(forKey: "weekSpent") ?? 0,
            localeCode: d?.string(forKey: "appLocale") ?? "system",
            draftAmount: max(1, min(rawDraftAmount, 9999))
        )
    }
}

// MARK: - View
//
// Layout philosophy:
//   • Use ViewThatFits / clear maxWidth limits so labels never clip on
//     the smallest devices.
//   • Headline numbers use minimumScaleFactor + lineLimit(1) so a wide
//     amount like "−$12,345" still fits.
//   • Quick-add column has a fixed width (94 pt) so the headline column
//     gets the rest of the medium widget — no horizontal squeeze.
//   • Padding is tight (12 pt) to give content room without looking
//     cramped on systemSmall.

struct TrackoraWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    private let background = Color(red: 0.812, green: 0.937, blue: 0.886)

    private var remaining: Double {
        guard entry.monthBudget > 0 else { return 0 }
        return entry.monthBudget - entry.budgetableSpent
    }
    private var isOver: Bool {
        entry.monthBudget > 0 && entry.budgetableSpent > entry.monthBudget
    }

    private func fmt(_ v: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let number = formatter.string(from: NSNumber(value: abs(v))) ?? String(format: "%.2f", abs(v))
        let separator = entry.currency.count > 1 ? " " : ""
        return "\(entry.currency)\(separator)\(number)"
    }

    private var languageCode: String {
        if entry.localeCode == "system" {
            return Locale.current.languageCode ?? "en"
        }
        return entry.localeCode
    }

    private func text(_ key: String) -> String {
        let zh = [
            "remaining": "剩余",
            "totalBalance": "总余额",
            "budgetQuickAdd": "预算快速添加",
            "quickAddExpense": "快速添加支出",
            "custom": "精确",
            "add": "添加",
        ]
        let ms = [
            "remaining": "Tinggal",
            "totalBalance": "Jumlah baki",
            "budgetQuickAdd": "Tambah bajet",
            "quickAddExpense": "Tambah pantas",
            "custom": "Tepat",
            "add": "Tambah",
        ]
        let en = [
            "remaining": "Remaining",
            "totalBalance": "Total balance",
            "budgetQuickAdd": "Budget quick add",
            "quickAddExpense": "Quick add expense",
            "custom": "Exact",
            "add": "Add",
        ]
        switch languageCode {
        case "zh":
            return zh[key] ?? en[key] ?? key
        case "ms":
            return ms[key] ?? en[key] ?? key
        default:
            return en[key] ?? key
        }
    }

    @ViewBuilder
    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content
                .containerBackground(for: .widget) { background }
        } else {
            content
                .background(background)
        }
    }

    private var content: some View {
        Group {
            if family == .systemSmall {
                smallView
            } else {
                mediumView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Small (2x2) ───────────────────────────────────────────
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            logoRow
            balanceBlock(titleSize: 10, valueSize: 21)
            Spacer(minLength: 0)
            quickGrid(compact: true)
        }
        .padding(12)
        // The `homeWidget=1` query is required so the home_widget Flutter
        // plugin recognises this as a widget URL and forwards it to the
        // Dart side via `HomeWidget.widgetClicked` /
        // `HomeWidget.initiallyLaunchedFromHomeWidget`. Without it the
        // plugin's `isWidgetUrl()` filter drops the URL.
        .widgetURL(URL(string: "trackora://quickadd?homeWidget=1"))
    }

    // ── Medium (4x2) ──────────────────────────────────────────
    private var mediumView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                logoRow
                balanceBlock(titleSize: 11, valueSize: 27)
                Spacer(minLength: 0)
                Text(entry.monthBudget > 0 ? text("budgetQuickAdd") : text("quickAddExpense"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.black.opacity(0.52))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            quickGrid(compact: false)
                .frame(width: 138)
        }
        .padding(14)
    }

    // Quick-add controls — adjust a draft amount, then add directly or
    // open the compact in-app Custom dialog.
    //
    // iOS 17+: the +/- controls update App Group defaults via
    //   `AdjustDraftAmountIntent`; Add runs `QuickAddExpenseIntent`
    //   without opening the app.
    // iOS 16 and earlier: fallback `Link` deep-links to the in-app
    //   compact quick-add sheet.
    //
    // The "Custom" button always deep-links to `trackora://quickadd`
    // because amount entry isn't possible inside a widget — Apple does
    // not provide a text-input affordance for widgets. Trackora opens
    // a small quick-add dialog rather than the full add screen.
    private func quickGrid(compact: Bool) -> some View {
        VStack(spacing: compact ? 5 : 6) {
            HStack(spacing: 5) {
                stepButton(delta: -1, compact: compact)
                draftAmountLabel(compact: compact)
                stepButton(delta: 1, compact: compact)
            }
            HStack(spacing: 5) {
                addDraftButton(compact: compact)
                customButton(compact: compact)
            }
        }
    }

    @ViewBuilder
    private func stepButton(delta: Double, compact: Bool) -> some View {
        let nextAmount = max(1, min(entry.draftAmount + delta, 9999))
        if #available(iOS 17.0, *) {
            Button(intent: AdjustDraftAmountIntent(delta: delta)) {
                stepButtonLabel(symbol: delta > 0 ? "+" : "−", compact: compact)
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: URL(string: "trackora://quickadd?amount=\(urlAmount(nextAmount))&homeWidget=1")!) {
                stepButtonLabel(symbol: delta > 0 ? "+" : "−", compact: compact)
            }
        }
    }

    private func stepButtonLabel(symbol: String, compact: Bool) -> some View {
        Text(symbol)
            .font(.system(size: compact ? 15 : 17, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .foregroundColor(.white)
            .frame(width: compact ? 25 : 31, height: compact ? 25 : 31)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous))
    }

    // The amount itself is tappable: it deep-links to the in-app
    // quick-add dialog with the current draft pre-filled, so users can
    // type the *exact* value instead of poking +/- repeatedly. The
    // +/- buttons remain for quick nudges.
    private func draftAmountLabel(compact: Bool) -> some View {
        Link(destination: URL(string: "trackora://quickadd?amount=\(urlAmount(entry.draftAmount))&homeWidget=1")!) {
            HStack(spacing: 3) {
                Text(fmt(entry.draftAmount))
                    .font(.system(size: compact ? 10 : 12, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundColor(.black)
                Image(systemName: "pencil")
                    .font(.system(size: compact ? 8 : 9, weight: .bold))
                    .foregroundColor(.black.opacity(0.45))
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 25 : 31)
            .padding(.horizontal, 3)
            .background(Color.white.opacity(0.76))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous))
        }
    }

    @ViewBuilder
    private func addDraftButton(compact: Bool) -> some View {
        if #available(iOS 17.0, *) {
            Button(intent: QuickAddExpenseIntent(amount: entry.draftAmount, category: "Food")) {
                actionButtonLabel(text("add"), compact: compact, filled: true)
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: URL(string: "trackora://quickadd?amount=\(urlAmount(entry.draftAmount))&homeWidget=1")!) {
                actionButtonLabel(text("add"), compact: compact, filled: true)
            }
        }
    }

    private func customButton(compact: Bool) -> some View {
        Link(destination: URL(string: "trackora://quickadd?homeWidget=1")!) {
            actionButtonLabel(text("custom"), compact: compact, filled: false)
        }
    }

    private func actionButtonLabel(_ title: String, compact: Bool, filled: Bool) -> some View {
        Text(title)
            .font(.system(size: compact ? 9 : 11, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .foregroundColor(filled ? .white : .black)
            .frame(maxWidth: .infinity, minHeight: compact ? 25 : 31)
            .background(filled ? Color.black : Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous))
    }

    private func urlAmount(_ amount: Double) -> String {
        String(format: "%.2f", amount)
    }

    private func balanceBlock(titleSize: CGFloat, valueSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.monthBudget > 0 ? text("remaining") : text("totalBalance"))
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundColor(.black.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(headlineText())
                .font(.system(size: valueSize, weight: .heavy, design: .rounded))
                .foregroundColor(isOver ? .red : .black)
                .minimumScaleFactor(0.42)
                .lineLimit(1)
            if entry.monthBudget > 0 {
                budgetProgress
                    .padding(.top, 4)
            }
        }
    }

    /// Compact iOS-style budget progress: usage percent + thin track.
    /// Bar tints amber from 80% and red when over budget so users get a
    /// glanceable warning without having to read numbers.
    private var budgetProgress: some View {
        let pct = entry.monthBudget > 0
            ? min(max(entry.budgetableSpent / entry.monthBudget, 0), 1.2)
            : 0
        let warn = pct >= 0.8 && pct < 1
        let barColor: Color = isOver ? .red : (warn ? Color(red: 0.85, green: 0.55, blue: 0.1) : Color.black.opacity(0.78))
        let percentText = "\(Int((pct * 100).rounded()))%"
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(percentText)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(barColor)
                Text("· \(fmt(entry.budgetableSpent)) / \(fmt(entry.monthBudget))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.black.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Color.black.opacity(0.10))
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(min(pct, 1)))
                }
            }
            .frame(height: 5)
        }
    }

    private func headlineText() -> String {
        if entry.monthBudget > 0 {
            return isOver
                ? "−" + fmt(entry.budgetableSpent - entry.monthBudget)
                : fmt(remaining)
        }
        return entry.savings >= 0 ? fmt(entry.savings) : "−" + fmt(abs(entry.savings))
    }

    private var logoRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 10))
                .foregroundColor(.black.opacity(0.7))
            Text("Trackora")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(.black.opacity(0.7))
                .lineLimit(1)
            Spacer()
        }
    }
}

// MARK: - Widget

@main
struct TrackoraWidget: Widget {
    let kind: String = "TrackoraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TrackoraWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Trackora")
        .description("See remaining balance and quick-add expenses without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
