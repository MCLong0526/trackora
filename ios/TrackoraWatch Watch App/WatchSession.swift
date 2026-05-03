import Foundation
import Combine
import WatchConnectivity

/// Reads spending summary from the shared App Group (written by the iPhone
/// app's WidgetSyncService) and sends "addExpense" messages back to the
/// phone via WatchConnectivity.
final class WatchSession: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSession()

    private let appGroup = "group.com.michaelchia.trackora"

    @Published var currency: String = "$"
    @Published var monthSpent: Double = 0       // total spent (everything)
    @Published var monthBudget: Double = 0
    @Published var savings: Double = 0          // current total balance (lifetime)
    @Published var budgetableSpent: Double = 0  // bills + installments excluded
    @Published var lastError: String?
    @Published var sending: Bool = false

    /// Budget left this month (bills + installments don't count).
    var budgetLeft: Double { max(monthBudget - budgetableSpent, 0) }
    var ratio: Double {
        guard monthBudget > 0 else { return 0 }
        return min(budgetableSpent / monthBudget, 1.0)
    }
    var isOver: Bool { monthBudget > 0 && budgetableSpent > monthBudget }

    private override init() {
        super.init()
    }

    func activate() {
        refresh()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    /// Pulls the latest numbers from the shared App Group UserDefaults.
    /// The iPhone app writes these whenever the dashboard rebuilds.
    func refresh() {
        guard let d = UserDefaults(suiteName: appGroup) else { return }
        currency = d.string(forKey: "currency") ?? "$"
        monthSpent = d.double(forKey: "monthSpent")
        monthBudget = d.double(forKey: "monthBudget")
        savings = d.double(forKey: "savings")
        // Older builds may not have written this key yet — fall back to total spent.
        let bs = d.double(forKey: "budgetableSpent")
        budgetableSpent = bs > 0 ? bs : monthSpent
    }

    /// Sends the new expense to the iPhone app. Phone must be reachable
    /// (Trackora open in foreground or recently active).
    func addExpense(amount: Double, category: String, note: String, completion: @escaping (Bool) -> Void) {
        guard WCSession.isSupported() else {
            lastError = "Watch Connectivity not supported."
            completion(false)
            return
        }
        let session = WCSession.default
        guard session.isReachable else {
            lastError = "iPhone not reachable. Open Trackora on your phone."
            completion(false)
            return
        }
        sending = true
        let payload: [String: Any] = [
            "type": "addExpense",
            "amount": amount,
            "category": category,
            "note": note,
        ]
        session.sendMessage(payload, replyHandler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.sending = false
                self?.lastError = nil
                completion(true)
            }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.sending = false
                self?.lastError = error.localizedDescription
                completion(false)
            }
        })
    }

    // MARK: WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.refresh() }
    }
}
