//
//  ContentView.swift
//  TrackoraWatch Watch App
//

import SwiftUI

// MARK: - Brand tokens (mirrors mobile app palette exactly)
private extension Color {
    static let accent     = Color(red: 0.561, green: 0.890, blue: 0.816) // #8FE3D0 — primary CTA
    static let accentSoft = Color(red: 0.812, green: 0.937, blue: 0.886) // #CFEFE2 — soft mint
    static let inkPrimary = Color(red: 0.949, green: 0.949, blue: 0.957) // #F2F2F4
    static let inkSoft    = Color(red: 0.631, green: 0.631, blue: 0.651) // #A1A1A6
    static let inkMuted   = Color(red: 0.300, green: 0.300, blue: 0.320)
    static let bg         = Color(red: 0.059, green: 0.059, blue: 0.071) // #0F0F12
    static let surface    = Color(red: 0.106, green: 0.106, blue: 0.125) // #1B1B20
    static let elevated   = Color(red: 0.165, green: 0.165, blue: 0.188) // #2A2A30
    static let income     = Color(red: 0.349, green: 0.761, blue: 0.541) // #59C28A
    static let expense    = Color(red: 0.914, green: 0.420, blue: 0.420) // #E96B6B
    static let lilac      = Color(red: 0.894, green: 0.843, blue: 0.961) // #E4D7F5
}

struct ContentView: View {
    @EnvironmentObject var session: WatchSession
    @State private var showingAdd = false

    private func fmt(_ v: Double) -> String {
        "\(session.currency)\(String(format: "%.2f", v))"
    }
    private func fmtRound(_ v: Double) -> String {
        "\(session.currency)\(String(format: "%.0f", v))"
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Int(-date.timeIntervalSinceNow)
        if diff < 5 { return "Just now" }
        if diff < 60 { return "\(diff)s ago" }
        if diff < 3600 { return "\(diff / 60)m ago" }
        return "\(diff / 3600)h ago"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    logoHeader
                    budgetCard
                    addButton
                    syncCard
                    if !session.recentExpenses.isEmpty {
                        recentExpensesSection
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(Color.bg)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAdd) {
                AddExpenseView()
                    .environmentObject(session)
            }
        }
    }

    // ── Logo header ────────────────────────────────────────────
    private var logoHeader: some View {
        HStack(spacing: 7) {
            Image("AppLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("Trackora")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(Color.inkPrimary)
            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    // ── Budget card ────────────────────────────────────────────
    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.accent)
                    .frame(width: 5, height: 5)
                Text("BUDGET")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(Color.inkSoft)
                    .tracking(0.8)
                Spacer()
                if session.hasData && session.monthBudget > 0 {
                    Text("\(Int(session.ratio * 100))%")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(session.isOver ? Color.expense : Color.inkSoft)
                }
            }

            if !session.hasData {
                noDataRow
            } else if session.monthBudget == 0 {
                Text("No budget set")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(Color.inkMuted)
                Text("Set on iPhone")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(Color.inkMuted)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.isOver
                         ? "−" + fmtRound(session.budgetableSpent - session.monthBudget)
                         : fmtRound(session.budgetLeft))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(session.isOver ? Color.expense : Color.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.elevated)
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(session.isOver ? Color.expense : Color.accent)
                                .frame(width: geo.size.width * CGFloat(min(session.ratio, 1.0)), height: 4)
                        }
                    }
                    .frame(height: 4)

                    Text("\(fmtRound(session.budgetableSpent)) of \(fmtRound(session.monthBudget))")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(Color.inkSoft)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.surface)
        )
    }

    @ViewBuilder
    private var noDataRow: some View {
        if session.syncStatus.isRequesting {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.55).frame(width: 14, height: 14)
                Text("Loading…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.inkMuted)
            }
        } else {
            Text("—")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Color.inkMuted)
        }
    }

    // ── Add button ─────────────────────────────────────────────
    private var addButton: some View {
        Button {
            showingAdd = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text("Add Expense")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color.accent)
            .foregroundColor(.black.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // ── Sync status card ───────────────────────────────────────
    private var syncCard: some View {
        HStack(spacing: 6) {
            syncStatusIndicator
            Text(syncStatusLabel)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(Color.inkMuted)
                .lineLimit(1)
            Spacer()
            if case .synced(let date) = session.syncStatus {
                Text(relativeTime(date))
                    .font(.system(size: 9))
                    .foregroundColor(Color.inkMuted)
            } else if case .failed = session.syncStatus {
                // nothing extra
            }
            syncButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surface)
        )
    }

    @ViewBuilder
    private var syncStatusIndicator: some View {
        switch session.syncStatus {
        case .requesting:
            ProgressView()
                .scaleEffect(0.45)
                .frame(width: 8, height: 8)
        case .synced:
            Circle().fill(Color.income).frame(width: 6, height: 6)
        case .offline, .idle:
            Circle().fill(Color.inkMuted).frame(width: 6, height: 6)
        case .queued:
            Circle().fill(Color(red: 1.0, green: 0.75, blue: 0.2)).frame(width: 6, height: 6)
        case .failed:
            Circle().fill(Color.expense).frame(width: 6, height: 6)
        @unknown default:
            Circle().fill(Color.inkMuted).frame(width: 6, height: 6)
        }
    }

    private var syncStatusLabel: String {
        switch session.syncStatus {
        case .requesting: return "Syncing…"
        case .synced:     return "Connected"
        case .offline:    return "Offline"
        case .queued:     return "Queued"
        case .failed:     return "Sync failed"
        case .idle:       return session.isPhoneReachable ? "Connected" : "Offline"
        }
    }

    @ViewBuilder
    private var syncButton: some View {
        if !session.syncStatus.isRequesting {
            Button {
                session.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.inkSoft)
                    .frame(width: 24, height: 24)
                    .background(Color.elevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // ── Recent expenses ────────────────────────────────────────
    private var recentExpensesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(Color.inkSoft)
                    .tracking(0.8)
                Spacer()
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(session.recentExpenses.prefix(5).enumerated()), id: \.element.id) { idx, expense in
                    VStack(spacing: 0) {
                        HStack(spacing: 9) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.elevated)
                                    .frame(width: 26, height: 26)
                                Image(systemName: categoryIcon(expense.category))
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.accent)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(expense.category)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color.inkPrimary)
                                if !expense.note.isEmpty {
                                    Text(expense.note)
                                        .font(.system(size: 9))
                                        .foregroundColor(Color.inkSoft)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(expense.type == "income" ? "+\(fmt(expense.amount))" : "-\(fmt(expense.amount))")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(expense.type == "income" ? Color.income : Color.expense)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)

                        if idx < session.recentExpenses.prefix(5).count - 1 {
                            Rectangle()
                                .fill(Color.elevated)
                                .frame(height: 0.5)
                                .padding(.leading, 45)
                        }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.surface))
        }
    }

    private func categoryIcon(_ cat: String) -> String {
        switch cat {
        case "Food":          return "fork.knife"
        case "Groceries":     return "cart"
        case "Transport":     return "car"
        case "Shopping":      return "bag"
        case "Entertainment": return "tv"
        case "Health":        return "heart"
        case "Bills":         return "doc.text"
        case "Income":        return "arrow.down.circle"
        default:              return "ellipsis.circle"
        }
    }
}
