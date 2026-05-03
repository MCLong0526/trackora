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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    logoHeader
                    totalBalanceCard
                    budgetCard
                    addButton
                    Button(action: { session.refresh() }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAdd) {
                AddExpenseView()
                    .environmentObject(session)
            }
        }
    }

    // ── Logo header ───────────────────────────────────────────
    private var logoHeader: some View {
        HStack(spacing: 6) {
            // Mint rounded-square chip with a stylized "T" mark.
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(red: 0.812, green: 0.937, blue: 0.886)) // mint
                    .frame(width: 22, height: 22)
                Text("T")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.black)
            }
            Text("Trackora")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.bottom, 2)
    }

    // ── Total balance (the user's actual money) ──────────────
    private var totalBalanceCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.561, green: 0.890, blue: 0.816))
                Text("Total balance")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            Text(session.savings >= 0 ? fmt(session.savings) : "−" + fmt(abs(session.savings)))
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .foregroundColor(session.savings >= 0 ? .white : .red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.black)
        )
    }

    // ── Budget left this month ───────────────────────────────
    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 10))
                Text("Budget left")
                    .font(.caption2)
                Spacer()
                if session.monthBudget > 0 {
                    Text("\(Int(session.ratio * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.black.opacity(0.6))

            if session.monthBudget == 0 {
                Text("Not set")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.black.opacity(0.55))
                Text("Set a budget on iPhone")
                    .font(.system(size: 9))
                    .foregroundColor(.black.opacity(0.55))
            } else {
                Text(session.isOver
                     ? "−" + fmtRound(session.budgetableSpent - session.monthBudget)
                     : fmtRound(session.budgetLeft))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(session.isOver ? .red : .black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.6))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(session.isOver ? Color.red : Color.black)
                            .frame(width: geo.size.width * CGFloat(session.ratio))
                    }
                }
                .frame(height: 5)

                Text("\(fmtRound(session.budgetableSpent)) of \(fmtRound(session.monthBudget))")
                    .font(.system(size: 9))
                    .foregroundColor(.black.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.812, green: 0.937, blue: 0.886)) // mint
        )
    }

    // ── Add button ───────────────────────────────────────────
    private var addButton: some View {
        Button {
            showingAdd = true
        } label: {
            Label("Add expense", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .tint(.black)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
