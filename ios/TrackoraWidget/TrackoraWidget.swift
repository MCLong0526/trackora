import WidgetKit
import SwiftUI
import ActivityKit

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
    /// Integer cents used by the large-widget numpad (widgetDraftCents key).
    let draftCents: Int
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
            draftAmount: 10,
            draftCents: 0
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
        let draftCents = d?.integer(forKey: "widgetDraftCents") ?? 0
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
            draftAmount: max(1, min(rawDraftAmount, 9999)),
            draftCents: max(0, min(draftCents, 999999))
        )
    }
}

// MARK: - Design Tokens

private let widgetBg          = Color(red: 0.07, green: 0.07, blue: 0.09)
private let widgetSurface     = Color(white: 1, opacity: 0.08)
private let widgetSurfaceHigh = Color(white: 1, opacity: 0.12)
private let widgetInk         = Color.white
private let widgetInkSoft     = Color.white.opacity(0.50)
private let widgetInkDim      = Color.white.opacity(0.30)
private let brandPurple       = Color(red: 0.380, green: 0.404, blue: 0.945)
private let expenseOrange     = Color(red: 0.965, green: 0.420, blue: 0.153)
private let incomeGreen       = Color(red: 0.133, green: 0.773, blue: 0.369)
private let receiveCyan       = Color(red: 0.024, green: 0.714, blue: 0.831)
private let transferAmber     = Color(red: 0.961, green: 0.620, blue: 0.043)

// MARK: - Widget Entry View

struct TrackoraWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    private var remaining: Double {
        guard entry.monthBudget > 0 else { return 0 }
        return entry.monthBudget - entry.budgetableSpent
    }
    private var isOver: Bool {
        entry.monthBudget > 0 && entry.budgetableSpent > entry.monthBudget
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        f.locale = Locale(identifier: "en_US_POSIX")
        let s = f.string(from: NSNumber(value: abs(v))) ?? String(format: "%.2f", abs(v))
        let sep = entry.currency.count > 1 ? " " : ""
        return "\(entry.currency)\(sep)\(s)"
    }

    private func fmtCents(_ cents: Int) -> String {
        fmt(Double(cents) / 100.0)
    }

    private var headlineText: String {
        if entry.monthBudget > 0 {
            return isOver
                ? "−" + fmt(entry.budgetableSpent - entry.monthBudget)
                : fmt(remaining)
        }
        return entry.savings >= 0 ? fmt(entry.savings) : "−" + fmt(abs(entry.savings))
    }

    private var headlineLabel: String {
        entry.monthBudget > 0 ? "Remaining" : "Balance"
    }

    private var headlineColor: Color {
        isOver ? .red : widgetInk
    }

    @ViewBuilder
    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) { widgetBg }
        } else {
            content.background(widgetBg)
        }
    }

    private var content: some View {
        Group {
            switch family {
            case .systemSmall:  smallView
            case .systemLarge:  largeView
            default:            mediumView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Small (2×2) ───────────────────────────────────────────────────────────

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            logoRow(size: 10)
            Spacer(minLength: 4)
            Text(headlineLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(widgetInkSoft)
                .lineLimit(1)
            Text(headlineText)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(headlineColor)
                .minimumScaleFactor(0.42)
                .lineLimit(1)
            if entry.monthBudget > 0 {
                budgetBar.padding(.top, 4)
            }
            Spacer(minLength: 6)
            todayRow
            Spacer(minLength: 6)
            quickAddPill
        }
        .padding(13)
        .widgetURL(URL(string: "trackora://quickadd?homeWidget=1"))
    }

    private var todayRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(widgetInkDim)
            Text("Today  \(fmt(entry.todaySpent))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(widgetInkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var quickAddPill: some View {
        Link(destination: URL(string: "trackora://quickadd?homeWidget=1")!) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .heavy))
                Text("Quick Add")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(widgetInk)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(brandPurple)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // ── Medium (4×2) ──────────────────────────────────────────────────────────

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                logoRow(size: 10)
                Spacer()
                statBadge(label: "Today", value: fmt(entry.todaySpent))
            }
            Spacer(minLength: 4)
            Text(headlineLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(widgetInkSoft)
                .lineLimit(1)
            Text(headlineText)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(headlineColor)
                .minimumScaleFactor(0.42)
                .lineLimit(1)
            if entry.monthBudget > 0 {
                budgetBar.padding(.top, 4)
            }
            Spacer(minLength: 10)
            mediumActionRow
        }
        .padding(14)
    }

    private var mediumActionRow: some View {
        HStack(spacing: 5) {
            actionTile(route: "add?type=expense",    icon: "minus",                       label: "Expense",  tint: expenseOrange, filled: true)
            actionTile(route: "add?type=income",     icon: "plus",                        label: "Income",   tint: incomeGreen)
            actionTile(route: "add?type=receive",    icon: "tray.and.arrow.down.fill",    label: "Receive",  tint: receiveCyan)
            actionTile(route: "add?type=transfer",   icon: "arrow.left.arrow.right",      label: "Transfer", tint: transferAmber)
            actionTile(route: "scan",                icon: "camera.fill",                 label: "Scan",     tint: brandPurple)
        }
    }

    // ── Large (4×4) ──────────────────────────────────────────────────────────

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                logoRow(size: 11)
                Spacer()
                statBadge(label: "Today", value: fmt(entry.todaySpent))
            }
            Spacer(minLength: 2)
            Text(headlineLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(widgetInkSoft)
                .lineLimit(1)
            Text(headlineText)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(headlineColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if entry.monthBudget > 0 {
                budgetBar.padding(.top, 3)
            }

            Spacer(minLength: 10)

            // Draft amount display
            draftAmountDisplay

            Spacer(minLength: 8)

            // Numpad
            numpad

            Spacer(minLength: 10)

            // Action row
            largeActionRow
        }
        .padding(14)
    }

    private var draftAmountDisplay: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(entry.currency)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(widgetInkSoft)
                .padding(.trailing, 3)
            Text(formatCentsForDisplay(entry.draftCents))
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundColor(entry.draftCents > 0 ? widgetInk : widgetInkDim)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func formatCentsForDisplay(_ cents: Int) -> String {
        let dollars = cents / 100
        let decimalPart = cents % 100
        let dollarsStr = dollars >= 1000
            ? "\(dollars / 1000),\(String(format: "%03d", dollars % 1000))"
            : "\(dollars)"
        return "\(dollarsStr).\(String(format: "%02d", decimalPart))"
    }

    private var numpad: some View {
        let rows: [[NumpadKey]] = [
            [.digit(1), .digit(2), .digit(3)],
            [.digit(4), .digit(5), .digit(6)],
            [.digit(7), .digit(8), .digit(9)],
            [.decimalLink, .digit(0), .backspace],
        ]
        return VStack(spacing: 5) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 5) {
                    ForEach(0..<rows[r].count, id: \.self) { c in
                        numpadButton(key: rows[r][c])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func numpadButton(key: NumpadKey) -> some View {
        switch key {
        case .digit(let d):
            if #available(iOS 17.0, *) {
                Button(intent: AppendDigitIntent(digit: d)) {
                    numpadKeyLabel(key)
                }
                .buttonStyle(.plain)
            } else {
                Link(destination: URL(string: "trackora://quickadd?homeWidget=1")!) {
                    numpadKeyLabel(key)
                }
            }
        case .backspace:
            if #available(iOS 17.0, *) {
                Button(intent: BackspaceDigitIntent()) {
                    numpadKeyLabel(key)
                }
                .buttonStyle(.plain)
            } else {
                Link(destination: URL(string: "trackora://quickadd?homeWidget=1")!) {
                    numpadKeyLabel(key)
                }
            }
        case .decimalLink:
            Link(destination: URL(string: "trackora://quickadd?homeWidget=1")!) {
                numpadKeyLabel(key)
            }
        }
    }

    private func numpadKeyLabel(_ key: NumpadKey) -> some View {
        Group {
            switch key {
            case .digit(let d):
                Text("\(d)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(widgetInk)
            case .backspace:
                Image(systemName: "delete.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(widgetInkSoft)
            case .decimalLink:
                Text("•••")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(widgetInkSoft)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(widgetSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var largeActionRow: some View {
        let draftStr = String(format: "%.2f", Double(entry.draftCents) / 100.0)
        return HStack(spacing: 5) {
            actionTile(route: "add?type=expense&amount=\(draftStr)",  icon: "minus",             label: "Expense",  tint: expenseOrange, filled: true)
            actionTile(route: "add?type=income&amount=\(draftStr)",   icon: "plus",              label: "Income",   tint: incomeGreen)
            actionTile(route: "add?type=receive&amount=\(draftStr)",  icon: "tray.and.arrow.down.fill", label: "Receive", tint: receiveCyan)
            actionTile(route: "scan",                                  icon: "camera.fill",       label: "Scan",     tint: brandPurple)
        }
    }

    // ── Shared subviews ───────────────────────────────────────────────────────

    private func logoRow(size: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: size, weight: .heavy))
                .foregroundColor(brandPurple)
            Text("Trackora")
                .font(.system(size: size + 1, weight: .heavy, design: .rounded))
                .foregroundColor(widgetInk)
                .lineLimit(1)
        }
    }

    private func statBadge(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(widgetInkDim)
            Text(value)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(widgetInkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var budgetBar: some View {
        let pct = entry.monthBudget > 0
            ? min(max(entry.budgetableSpent / entry.monthBudget, 0), 1.2)
            : 0
        let warn = pct >= 0.8 && pct < 1
        let barColor: Color = isOver ? .red : (warn ? transferAmber : brandPurple)
        let percentText = "\(Int((pct * 100).rounded()))%"
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(percentText)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(barColor)
                Text("· \(fmt(entry.budgetableSpent)) / \(fmt(entry.monthBudget))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(widgetInkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(min(pct, 1)))
                }
            }
            .frame(height: 4)
        }
    }

    private func actionTile(route: String, icon: String, label: String, tint: Color, filled: Bool = false) -> some View {
        Link(destination: widgetRoute(route)) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(filled ? .white : tint)
                Text(label)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(filled ? .white : widgetInk.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(filled ? tint : widgetSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(filled ? tint.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Numpad Key

private enum NumpadKey {
    case digit(Int)
    case backspace
    case decimalLink
}

// MARK: - Route Helper

private func widgetRoute(_ route: String) -> URL {
    let sep = route.contains("?") ? "&" : "?"
    return URL(string: "trackora://\(route)\(sep)homeWidget=1")!
}

// MARK: - Home Screen Widget

struct TrackoraWidget: Widget {
    let kind: String = "TrackoraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TrackoraWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Trackora")
        .description("Balance, budget progress, and quick-add shortcuts.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Live Activity

// iOS 16.2+ required: newer SDKs mandate the dynamicIsland: parameter.
// On devices without a Dynamic Island (e.g. iPhone SE) the dynamic island
// content is simply never shown — the Lock Screen banner still appears.
@available(iOSApplicationExtension 16.2, *)
struct TrackoraLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackoraLiveActivityAttributes.self) { context in
            TrackoraLiveActivityLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    liveIslandBrandHeader()
                    .padding(.leading, 10)
                    .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    liveIslandOpenLink()
                    .padding(.trailing, 12)
                    .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    liveIslandQuickEntryPanel(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(liveBrandPurple)
                    .padding(.leading, 4)
            } compactTrailing: {
                Text(fmtAmount(context.state.todaySpent, currency: context.state.currency))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                    .padding(.trailing, 4)
            } minimal: {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(liveBrandPurple)
            }
            .widgetURL(liveRoute("add"))
            .keylineTint(liveBrandPurple)
        }
    }
}

/// Minimal lock-screen banner — ActivityKit requires a content closure but we
/// keep it unobtrusive since Dynamic Island is the primary interaction surface.
@available(iOSApplicationExtension 16.2, *)
private struct TrackoraLiveActivityLockScreenView: View {
    let state: TrackoraLiveActivityAttributes.ContentState

    var body: some View {
        Link(destination: liveRoute("add")) {
            HStack(spacing: 8) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(liveBrandPurple)
                Text("Trackora")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.80))
                Spacer(minLength: 0)
                Text(fmtAmount(state.todaySpent, currency: state.currency))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black)
    }
}

// MARK: - Shared Live Activity Helpers

private let liveBrandPurple   = Color(red: 0.380, green: 0.404, blue: 0.945)
private let liveExpenseOrange = Color(red: 0.965, green: 0.420, blue: 0.153)
private let liveIncomeGreen   = Color(red: 0.133, green: 0.773, blue: 0.369)
private let liveReceiveCyan   = Color(red: 0.024, green: 0.714, blue: 0.831)
private let liveTransferAmber = Color(red: 0.961, green: 0.620, blue: 0.043)

private func liveRoute(_ route: String) -> URL {
    let separator = route.contains("?") ? "&" : "?"
    return URL(string: "trackora://\(route)\(separator)homeWidget=1")!
}

private func liveIslandBrandHeader() -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(liveBrandPurple)
            Text("Trackora")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.84))
        }
        Text("Quick entry")
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(.white.opacity(0.48))
    }
}

private func liveIslandOpenLink() -> some View {
    Link(destination: liveRoute("add")) {
        VStack(spacing: 3) {
            Image(systemName: "arrow.up.right.square.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(liveBrandPurple)
            Text("Open")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.58))
        }
    }
}

/// Dynamic Island expanded bottom panel.
/// Real text input is not supported by ActivityKit, so actions deep-link into
/// the app's existing quick-add / OCR flows.
@available(iOSApplicationExtension 16.2, *)
private func liveIslandQuickEntryPanel(
    state: TrackoraLiveActivityAttributes.ContentState
) -> some View {
    VStack(spacing: 10) {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("TODAY'S SPENDING")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(.white.opacity(0.40))
                Text(fmtAmount(state.todaySpent, currency: state.currency))
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.50)
            }
            Spacer(minLength: 8)
            Link(destination: liveRoute("add")) {
                HStack(spacing: 3) {
                    Text("Open")
                        .font(.system(size: 10, weight: .bold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.white.opacity(0.50))
            }
        }

        HStack(spacing: 5) {
            liveIslandActionLink(route: "add?type=expense", icon: "minus",                    label: "Expense",  tint: liveExpenseOrange, filled: true)
            liveIslandActionLink(route: "add?type=income",  icon: "plus",                     label: "Income",   tint: liveIncomeGreen)
            liveIslandActionLink(route: "add?type=receive", icon: "tray.and.arrow.down.fill", label: "Receive",  tint: liveReceiveCyan)
            liveIslandActionLink(route: "add?type=transfer",icon: "arrow.left.arrow.right",   label: "Transfer", tint: liveTransferAmber)
            liveIslandActionLink(route: "scan",             icon: "camera.fill",              label: "Scan",     tint: liveBrandPurple)
        }
    }
    .padding(.horizontal, 12)
    .padding(.top, 4)
    .padding(.bottom, 10)
}

private func liveIslandActionLink(
    route: String,
    icon: String,
    label: String,
    tint: Color,
    filled: Bool = false
) -> some View {
    Link(destination: liveRoute(route)) {
        liveIslandActionTile(icon: icon, label: label, tint: tint, filled: filled)
    }
}

private func liveIslandActionTile(
    icon: String,
    label: String,
    tint: Color,
    filled: Bool
) -> some View {
    VStack(spacing: 4) {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .heavy))
            .foregroundColor(filled ? .white : tint)
        Text(label)
            .font(.system(size: 8, weight: .heavy))
            .foregroundColor(filled ? .white : .white.opacity(0.74))
            .lineLimit(1)
            .minimumScaleFactor(0.68)
    }
    .frame(maxWidth: .infinity, minHeight: 42)
    .background(filled ? tint : Color.white.opacity(0.075))
    .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(filled ? tint.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
}

private func fmtAmount(_ value: Double, currency: String) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    f.usesGroupingSeparator = true
    f.locale = Locale(identifier: "en_US_POSIX")
    let s = f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    let sep = currency.count > 1 ? " " : ""
    return "\(currency)\(sep)\(s)"
}

// MARK: - Widget Bundle

@main
struct TrackoraWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrackoraWidget()
        if #available(iOSApplicationExtension 16.2, *) {
            TrackoraLiveActivityWidget()
        }
    }
}
