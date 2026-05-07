//
//  ContentView.swift
//  TrackoraWatch Watch App
//

import SwiftUI

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
                VStack(spacing: 10) {
                    logoHeader
                    balanceCard
                    budgetCard
                    addButton
                    syncCard
                    if !session.recentExpenses.isEmpty {
                        recentExpensesSection
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .background(Color(white: 0.08))
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAdd) {
                AddExpenseView()
                    .environmentObject(session)
            }
        }
    }

    // ── Logo header ────────────────────────────────────────────
    private var logoHeader: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.812, green: 0.937, blue: 0.886))
                    .frame(width: 20, height: 20)
                Text("T")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Color(white: 0.1))
            }
            Text("Trackora")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    // ── Balance card ───────────────────────────────────────────
    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(Color(red: 0.812, green: 0.937, blue: 0.886))
                Text("TOTAL BALANCE")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.5)
            }
            if !session.hasData {
                noDataPlaceholder
            } else {
                Text(session.savings >= 0
                     ? fmt(session.savings)
                     : "−" + fmt(abs(session.savings)))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundColor(session.savings >= 0
                        ? Color(red: 0.812, green: 0.937, blue: 0.886)
                        : Color(red: 1.0, green: 0.45, blue: 0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.15))
        )
    }

    @ViewBuilder
    private var noDataPlaceholder: some View {
        if session.syncStatus.isRequesting {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                Text("Loading…")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(white: 0.4))
            }
        } else {
            Text("—")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(Color(white: 0.3))
        }
    }

    // ── Budget card ────────────────────────────────────────────
    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(Color(red: 0.812, green: 0.937, blue: 0.886))
                Text("BUDGET LEFT")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(white: 0.45))
                    .tracking(0.5)
                Spacer()
                if session.hasData && session.monthBudget > 0 {
                    Text("\(Int(session.ratio * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(Color(white: 0.45))
                }
            }

            if !session.hasData {
                Text(session.syncStatus.isRequesting ? "Loading…" : "—")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(white: 0.3))
            } else if session.monthBudget == 0 {
                Text("No budget set")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(white: 0.5))
                Text("Set on iPhone")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(white: 0.4))
            } else {
                Text(session.isOver
                     ? "−" + fmtRound(session.budgetableSpent - session.monthBudget)
                     : fmtRound(session.budgetLeft))
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(session.isOver
                        ? Color(red: 1.0, green: 0.45, blue: 0.45)
                        : Color(red: 0.812, green: 0.937, blue: 0.886))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(white: 0.22))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(session.isOver
                                ? Color(red: 1.0, green: 0.45, blue: 0.45)
                                : Color(red: 0.812, green: 0.937, blue: 0.886))
                            .frame(width: geo.size.width * CGFloat(session.ratio), height: 4)
                    }
                }
                .frame(height: 4)

                Text("\(fmtRound(session.budgetableSpent)) / \(fmtRound(session.monthBudget))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(white: 0.4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.13))
        )
    }

    // ── Add button ─────────────────────────────────────────────
    private var addButton: some View {
        Button {
            showingAdd = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Add Expense")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(red: 0.812, green: 0.937, blue: 0.886))
            .foregroundColor(Color(white: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // ── Sync status card ───────────────────────────────────────
    // Shows real connectivity state and lets user trigger manual sync.
    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                syncStatusIndicator
                Text(syncStatusLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(white: 0.35))
                Spacer()
                syncButton
            }

            if case .synced(let date) = session.syncStatus {
                Text("Updated \(relativeTime(date))")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.28))
                    .padding(.leading, 9)
            } else if case .failed(let msg) = session.syncStatus {
                Text(msg)
                    .font(.system(size: 9))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                    .lineLimit(2)
                    .padding(.leading, 9)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.11))
        )
    }

    @ViewBuilder
    private var syncStatusIndicator: some View {
        switch session.syncStatus {
        case .requesting:
            ProgressView()
                .scaleEffect(0.45)
                .frame(width: 7, height: 7)
        case .synced:
            Circle()
                .fill(Color(red: 0.812, green: 0.937, blue: 0.886))
                .frame(width: 6, height: 6)
        case .offline, .idle:
            Circle()
                .fill(Color(white: 0.3))
                .frame(width: 6, height: 6)
        case .queued:
            Circle()
                .fill(Color(red: 1.0, green: 0.75, blue: 0.2))
                .frame(width: 6, height: 6)
        case .failed:
            Circle()
                .fill(Color(red: 1.0, green: 0.45, blue: 0.45))
                .frame(width: 6, height: 6)
        @unknown default:
            Circle()
                .fill(Color(white: 0.3))
                .frame(width: 6, height: 6)
        }
    }

    private var syncStatusLabel: String {
        switch session.syncStatus {
        case .requesting: return "Syncing…"
        case .synced: return "iPhone connected"
        case .offline: return "iPhone offline"
        case .queued: return "Queued — will sync"
        case .failed: return "Sync failed"
        case .idle: return session.isPhoneReachable ? "iPhone connected" : "iPhone offline"
        }
    }

    @ViewBuilder
    private var syncButton: some View {
        if !session.syncStatus.isRequesting {
            Button {
                session.refresh()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Sync")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(Color(white: 0.4))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(white: 0.18))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
    }

    // ── Recent expenses ────────────────────────────────────────
    private var recentExpensesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(Color(white: 0.4))
                .tracking(0.5)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(session.recentExpenses.prefix(5).enumerated()), id: \.element.id) { idx, expense in
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: categoryIcon(expense.category))
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 0.812, green: 0.937, blue: 0.886))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(expense.category)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                if !expense.note.isEmpty {
                                    Text(expense.note)
                                        .font(.system(size: 9))
                                        .foregroundColor(Color(white: 0.4))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(expense.type == "income" ? "+\(fmt(expense.amount))" : "-\(fmt(expense.amount))")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(expense.type == "income"
                                    ? Color(red: 0.812, green: 0.937, blue: 0.886)
                                    : Color(red: 1.0, green: 0.45, blue: 0.45))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)

                        if idx < session.recentExpenses.prefix(5).count - 1 {
                            Rectangle()
                                .fill(Color(white: 0.18))
                                .frame(height: 0.5)
                                .padding(.leading, 36)
                        }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
        }
    }

    private func categoryIcon(_ cat: String) -> String {
        switch cat {
        case "Food": return "fork.knife"
        case "Groceries": return "cart"
        case "Transport": return "car"
        case "Shopping": return "bag"
        case "Entertainment": return "tv"
        case "Health": return "heart"
        case "Bills": return "doc.text"
        case "Income": return "arrow.down.circle"
        default: return "ellipsis.circle"
        }
    }
}
