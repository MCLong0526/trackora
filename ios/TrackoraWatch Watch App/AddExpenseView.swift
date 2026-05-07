import SwiftUI

struct AddExpenseView: View {
    @EnvironmentObject var session: WatchSession
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double = 0
    @State private var category: String = "Food"
    @State private var note: String = ""
    @State private var selectedAccountId: String? = nil
    @State private var saving = false
    @State private var error: String?

    private let categories = [
        "Food", "Groceries", "Transport", "Shopping",
        "Entertainment", "Health", "Bills", "Others",
    ]
    private let quickAmounts: [Double] = [5, 10, 20, 50, 100]

    private func fmt(_ v: Double) -> String {
        "\(session.currency)\(String(format: "%.2f", v))"
    }

    private func iconName(_ cat: String) -> String {
        switch cat {
        case "Food": return "fork.knife"
        case "Groceries": return "cart"
        case "Transport": return "car"
        case "Shopping": return "bag"
        case "Entertainment": return "tv"
        case "Health": return "heart"
        case "Bills": return "doc.text"
        default: return "ellipsis.circle"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                headerRow
                amountSection
                quickAmountRow
                categorySection
                if !session.accounts.isEmpty {
                    accountSection
                }
                if let error {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }
                saveButton
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(Color(white: 0.08))
        .navigationBarHidden(true)
    }

    // ── Header ──────────────────────────────────────────────────
    private var headerRow: some View {
        HStack {
            Text("New Expense")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(white: 0.5))
                    .frame(width: 22, height: 22)
                    .background(Color(white: 0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // ── Amount display ──────────────────────────────────────────
    private var amountSection: some View {
        VStack(spacing: 4) {
            Text(fmt(amount))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .foregroundColor(amount > 0
                    ? Color(red: 0.812, green: 0.937, blue: 0.886)
                    : Color(white: 0.35))
                .padding(.vertical, 12)
                .background(Color(white: 0.13))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .focusable(true)
                .digitalCrownRotation(
                    $amount,
                    from: 0,
                    through: 100000,
                    by: 0.5,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
            Text("Turn crown to set amount")
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.35))
        }
    }

    // ── Quick amounts ───────────────────────────────────────────
    private var quickAmountRow: some View {
        HStack(spacing: 5) {
            ForEach(quickAmounts, id: \.self) { v in
                Button("+\(Int(v))") {
                    amount += v
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(white: 0.18))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.plain)
            }
            Button(action: { amount = 0 }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.4))
                    .frame(width: 28, height: 28)
                    .background(Color(white: 0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    // ── Category grid ───────────────────────────────────────────
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CATEGORY")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(Color(white: 0.4))
                .tracking(0.5)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 6
            ) {
                ForEach(categories, id: \.self) { c in
                    Button {
                        category = c
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: iconName(c))
                                .font(.system(size: 10))
                            Text(c)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(category == c
                            ? Color(red: 0.812, green: 0.937, blue: 0.886)
                            : Color(white: 0.16))
                        .foregroundColor(category == c ? Color(white: 0.1) : Color(white: 0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ── Account picker ──────────────────────────────────────────
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACCOUNT")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(Color(white: 0.4))
                .tracking(0.5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // "None" option
                    Button {
                        selectedAccountId = nil
                    } label: {
                        Text("None")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedAccountId == nil
                                ? Color(red: 0.812, green: 0.937, blue: 0.886)
                                : Color(white: 0.16))
                            .foregroundColor(selectedAccountId == nil
                                ? Color(white: 0.1) : Color(white: 0.65))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    ForEach(session.accounts) { account in
                        Button {
                            selectedAccountId = account.id
                        } label: {
                            Text(account.name)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedAccountId == account.id
                                    ? Color(red: 0.812, green: 0.937, blue: 0.886)
                                    : Color(white: 0.16))
                                .foregroundColor(selectedAccountId == account.id
                                    ? Color(white: 0.1) : Color(white: 0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // ── Save button ─────────────────────────────────────────────
    private var saveButton: some View {
        Button {
            guard amount > 0 else {
                error = "Enter an amount"
                return
            }
            error = nil
            saving = true
            session.addExpense(amount: amount, category: category, note: note, accountId: selectedAccountId) { ok in
                saving = false
                if ok {
                    dismiss()
                } else {
                    error = session.lastError ?? "Could not reach iPhone"
                }
            }
        } label: {
            if saving {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("Save")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(amount > 0
                    ? Color(red: 0.812, green: 0.937, blue: 0.886)
                    : Color(white: 0.2))
                .foregroundColor(amount > 0 ? Color(white: 0.1) : Color(white: 0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .buttonStyle(.plain)
        .disabled(saving || amount <= 0)
    }
}
