import SwiftUI

struct AddExpenseView: View {
    @EnvironmentObject var session: WatchSession
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double = 0
    @State private var category: String = "Food"
    @State private var note: String = ""
    @State private var saving = false
    @State private var error: String?

    /// Categories the iPhone app already understands (`kCategoryStyles`
    /// in lib/theme/app_theme.dart). Keep in sync if you add new ones.
    private let categories = [
        "Food", "Groceries", "Transport", "Shopping",
        "Entertainment", "Health", "Bills", "Others",
    ]

    private let quickAmounts: [Double] = [5, 10, 20, 50, 100]

    private func fmt(_ v: Double) -> String {
        "\(session.currency)\(String(format: "%.2f", v))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                amountSection
                categorySection
                if let error {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                saveButton
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("New expense")
    }

    private var amountSection: some View {
        VStack(spacing: 8) {
            // Digital Crown amount picker — turn the crown to dial in the value.
            Text(fmt(amount))
                .font(.system(size: 28, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.812, green: 0.937, blue: 0.886))
                )
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
            HStack(spacing: 6) {
                ForEach(quickAmounts, id: \.self) { v in
                    Button("+\(Int(v))") {
                        amount += v
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .font(.caption2)
                }
                Button(action: { amount = 0 }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Category")
                .font(.caption2)
                .foregroundColor(.secondary)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 6
            ) {
                ForEach(categories, id: \.self) { c in
                    Button {
                        category = c
                    } label: {
                        Text(c)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(category == c
                                          ? Color.primary
                                          : Color.gray.opacity(0.2))
                            )
                            .foregroundColor(category == c
                                             ? Color.white
                                             : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            guard amount > 0 else {
                error = "Enter an amount."
                return
            }
            error = nil
            saving = true
            session.addExpense(amount: amount, category: category, note: note) { ok in
                saving = false
                if ok {
                    dismiss()
                } else {
                    error = session.lastError ?? "Could not send to iPhone."
                }
            }
        } label: {
            if saving {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Label("Save", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
        }
        .tint(.black)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(saving || amount <= 0)
    }
}
