import Foundation
import AppIntents
import WidgetKit

private let trackoraAppGroup = "group.com.michaelchia.trackora"

/// Background AppIntent invoked from the widget's quick-add buttons.
/// Writes the pending entry into shared App Group UserDefaults as a
/// JSON queue (`pending_widget_expenses_json`). The Flutter app drains
/// the queue on launch / resume and persists each entry through the
/// active `ExpenseRepository`.
///
/// `openAppWhenRun = false` means tapping the button does NOT open
/// Trackora — the entry is captured silently and the widget is reloaded.
/// On iOS < 17 the widget falls back to deep-linking to the in-app
/// add screen, so users on older OS still get the same outcome.
@available(iOS 17.0, *)
struct QuickAddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick add expense"
    static var description = IntentDescription("Add a small expense from the home-screen widget without opening Trackora.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "Category") var category: String

    init() {
        self.amount = 0
        self.category = "Food"
    }

    init(amount: Double, category: String) {
        self.amount = amount
        self.category = category
    }

    func perform() async throws -> some IntentResult {
        guard amount > 0,
              let defaults = UserDefaults(suiteName: trackoraAppGroup) else {
            return .result()
        }

        var queue: [[String: Any]] = []
        if let raw = defaults.string(forKey: "pending_widget_expenses_json"),
           let data = raw.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            queue = parsed
        }

        queue.append([
            "id": UUID().uuidString,
            "amount": amount,
            "category": category,
            "ts": Int(Date().timeIntervalSince1970 * 1000),
        ])

        if let data = try? JSONSerialization.data(withJSONObject: queue),
           let str = String(data: data, encoding: .utf8) {
            defaults.set(str, forKey: "pending_widget_expenses_json")
        }

        // Optimistically bump local "spent today/week" counters so the
        // widget reflects the new entry immediately, before the Flutter
        // app has a chance to drain the queue and re-push numbers.
        let todaySpent = defaults.double(forKey: "todaySpent")
        let weekSpent = defaults.double(forKey: "weekSpent")
        let monthSpent = defaults.double(forKey: "monthSpent")
        let budgetable = defaults.double(forKey: "budgetableSpent")
        let savings = defaults.double(forKey: "savings")
        defaults.set(todaySpent + amount, forKey: "todaySpent")
        defaults.set(weekSpent + amount, forKey: "weekSpent")
        defaults.set(monthSpent + amount, forKey: "monthSpent")
        defaults.set(budgetable + amount, forKey: "budgetableSpent")
        defaults.set(savings - amount, forKey: "savings")

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Updates the widget's draft amount for the +/- controls (small/medium widget).
///
/// This stays entirely in the widget extension through App Group
/// UserDefaults, so tapping +/- does not open Trackora on iOS 17+.
@available(iOS 17.0, *)
struct AdjustDraftAmountIntent: AppIntent {
    static var title: LocalizedStringResource = "Adjust quick amount"
    static var description = IntentDescription("Change the quick-add amount shown in the Trackora widget.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Delta") var delta: Double

    init() {
        self.delta = 0
    }

    init(delta: Double) {
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        guard let defaults = UserDefaults(suiteName: trackoraAppGroup) else {
            return .result()
        }

        let current = defaults.double(forKey: "widgetDraftAmount")
        let base = current > 0 ? current : 10
        let next = min(max(base + delta, 1), 9999)
        defaults.set(next, forKey: "widgetDraftAmount")

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Appends a digit to the large-widget numpad draft amount (integer cents).
/// Tapping "5" on the numpad calls AppendDigitIntent(digit: 5).
/// Amounts are stored as integer cents in `widgetDraftCents`:
///   current=125 (=$1.25), digit=3 → new=1253 (=$12.53)
@available(iOS 17.0, *)
struct AppendDigitIntent: AppIntent {
    static var title: LocalizedStringResource = "Append digit to draft amount"
    static var description = IntentDescription("Build up a quick-add amount digit by digit on the large Trackora widget.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Digit") var digit: Int

    init() { self.digit = 0 }
    init(digit: Int) { self.digit = digit }

    func perform() async throws -> some IntentResult {
        guard let defaults = UserDefaults(suiteName: trackoraAppGroup) else { return .result() }
        let current = defaults.integer(forKey: "widgetDraftCents")
        let next = min(current * 10 + digit, 999999) // max $9,999.99
        defaults.set(next, forKey: "widgetDraftCents")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Removes the last digit from the large-widget numpad draft amount.
@available(iOS 17.0, *)
struct BackspaceDigitIntent: AppIntent {
    static var title: LocalizedStringResource = "Remove last digit from draft amount"
    static var description = IntentDescription("Delete the last digit typed on the large Trackora widget numpad.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        guard let defaults = UserDefaults(suiteName: trackoraAppGroup) else { return .result() }
        let current = defaults.integer(forKey: "widgetDraftCents")
        defaults.set(current / 10, forKey: "widgetDraftCents")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
