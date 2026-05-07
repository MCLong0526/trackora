import Foundation
import Combine
import WatchConnectivity

/// Reads spending summary pushed by the iPhone app via WCSession applicationContext
/// (and as a fallback from the shared App Group written by WidgetSyncService).
/// Sends "addExpense" messages back to the phone via transferUserInfo so they
/// are queued and delivered reliably even when the phone app is backgrounded.
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
        } else {
            // Already activated — pull any applicationContext the phone has sent.
            applyContext(session.receivedApplicationContext)
        }
    }

    /// Pulls the latest numbers from the shared App Group UserDefaults.
    /// The iPhone app writes these whenever the dashboard rebuilds.
    func refresh() {
        guard let d = UserDefaults(suiteName: appGroup) else { return }
        let sym = d.string(forKey: "currency") ?? ""
        if !sym.isEmpty { currency = sym }
        let ms = d.double(forKey: "monthSpent")
        if ms > 0 { monthSpent = ms }
        let mb = d.double(forKey: "monthBudget")
        if mb > 0 { monthBudget = mb }
        let sv = d.double(forKey: "savings")
        // savings can be negative, so check the key exists
        if d.object(forKey: "savings") != nil { savings = sv }
        let bs = d.double(forKey: "budgetableSpent")
        budgetableSpent = bs > 0 ? bs : monthSpent
    }

    /// Applies data delivered via WCSession applicationContext.
    private func applyContext(_ ctx: [String: Any]) {
        guard !ctx.isEmpty else { return }
        if let sym = ctx["currency"] as? String, !sym.isEmpty { currency = sym }
        if let v = ctx["monthSpent"] as? Double { monthSpent = v }
        if let v = ctx["monthBudget"] as? Double { monthBudget = v }
        if let v = ctx["savings"] as? Double { savings = v }
        if let v = ctx["budgetableSpent"] as? Double {
            budgetableSpent = v > 0 ? v : monthSpent
        }
    }

    /// Queues the new expense for delivery to the iPhone app.
    /// Uses transferUserInfo so delivery is guaranteed even when the phone
    /// app is backgrounded — no reachability check needed.
    func addExpense(amount: Double, category: String, note: String, completion: @escaping (Bool) -> Void) {
        guard WCSession.isSupported() else {
            lastError = "Watch Connectivity not supported."
            completion(false)
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            lastError = "Session not activated yet."
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
        // transferUserInfo queues the payload and delivers it when the phone app
        // is next active — no replyHandler, no reachability requirement.
        session.transferUserInfo(payload)
        DispatchQueue.main.async {
            self.sending = false
            self.lastError = nil
            completion(true)
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.refresh()
            // Also pull any context the phone has already sent.
            self.applyContext(session.receivedApplicationContext)
        }
    }

    /// Receives data pushed by the phone via updateApplicationContext.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.applyContext(applicationContext)
        }
    }
}
