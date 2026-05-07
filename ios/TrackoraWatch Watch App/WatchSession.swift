import Foundation
import Combine
import WatchConnectivity

// MARK: - Models

struct WatchExpense: Identifiable {
    var id: String
    var amount: Double
    var category: String
    var note: String
    var type: String  // "expense" | "income" | "transfer" | "receive"
    var date: Date
}

struct WatchAccount: Identifiable {
    var id: String
    var name: String
}

// MARK: - SyncStatus

enum SyncStatus: Equatable {
    case idle
    case requesting
    case synced(Date)
    case offline
    case queued
    case failed(String)

    var isRequesting: Bool {
        if case .requesting = self { return true }
        return false
    }

    static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.requesting, .requesting),
             (.offline, .offline), (.queued, .queued):
            return true
        case (.synced(let a), .synced(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - WatchSession

/// Manages data exchange between the watchOS app and its paired iPhone app.
///
/// Phone → Watch:
///   • WCSession applicationContext (pushed by WidgetSyncService on every dashboard rebuild)
///   • Shared App Group UserDefaults (same group.com.michaelchia.trackora container)
///
/// Watch → Phone:
///   • transferUserInfo (queued, delivered when phone app opens)
///     – type "addExpense": create a new expense in Firebase via WatchService.dart
final class WatchSession: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSession()

    private let appGroup = "group.com.michaelchia.trackora"

    // MARK: Published state

    @Published var currency: String = "$"
    @Published var monthSpent: Double = 0
    @Published var monthBudget: Double = 0
    @Published var savings: Double = 0
    @Published var budgetableSpent: Double = 0
    @Published var recentExpenses: [WatchExpense] = []
    @Published var accounts: [WatchAccount] = []
    @Published var lastError: String?
    @Published var sending: Bool = false
    @Published var syncStatus: SyncStatus = .idle

    private var _hasData: Bool = false

    // MARK: Computed

    var hasData: Bool { _hasData }
    var budgetLeft: Double { max(monthBudget - budgetableSpent, 0) }
    var ratio: Double {
        guard monthBudget > 0 else { return 0 }
        return min(budgetableSpent / monthBudget, 1.0)
    }
    var isOver: Bool { monthBudget > 0 && budgetableSpent > monthBudget }
    var isPhoneReachable: Bool {
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isReachable
    }

    private override init() { super.init() }

    // MARK: Activation

    func activate() {
        guard WCSession.isSupported() else {
            syncStatus = .offline
            return
        }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        } else {
            // Already active — apply any context the phone already sent.
            let ctx = session.receivedApplicationContext
            if !ctx.isEmpty { applyContext(ctx) }
            if !_hasData { readFromAppGroup() }
            syncStatus = _hasData ? .synced(Date()) : .offline
        }
    }

    // MARK: Refresh (called by the Sync button)

    func refresh() {
        guard WCSession.isSupported() else {
            syncStatus = _hasData ? .synced(Date()) : .offline
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            syncStatus = _hasData ? .synced(Date()) : .offline
            return
        }

        syncStatus = .requesting

        // 1. Read the latest values from the shared App Group (fast, no network).
        readFromAppGroup()

        // 2. Apply the most recent applicationContext the phone has sent.
        let ctx = session.receivedApplicationContext
        if !ctx.isEmpty { applyContext(ctx) }

        if _hasData {
            syncStatus = .synced(Date())
        } else if session.isReachable {
            // 3. Phone is in foreground — ask it for a fresh push.
            session.sendMessage(["type": "requestSync"], replyHandler: { [weak self] reply in
                DispatchQueue.main.async {
                    self?.applyContext(reply)
                    self?.syncStatus = .synced(Date())
                }
            }, errorHandler: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.syncStatus = self?._hasData == true ? .synced(Date()) : .offline
                }
            })
        } else {
            syncStatus = .offline
        }
    }

    // MARK: - Private helpers

    private func readFromAppGroup() {
        guard let d = UserDefaults(suiteName: appGroup) else { return }
        if let sym = d.string(forKey: "currency"), !sym.isEmpty { currency = sym; _hasData = true }
        let ms = d.double(forKey: "monthSpent")
        if ms > 0 { monthSpent = ms; _hasData = true }
        let mb = d.double(forKey: "monthBudget")
        if mb > 0 { monthBudget = mb }
        if d.object(forKey: "savings") != nil { savings = d.double(forKey: "savings"); _hasData = true }
        let bs = d.double(forKey: "budgetableSpent")
        budgetableSpent = bs > 0 ? bs : monthSpent
    }

    private func applyContext(_ ctx: [String: Any]) {
        guard !ctx.isEmpty else { return }
        if let sym = ctx["currency"] as? String, !sym.isEmpty { currency = sym }
        if let v = ctx["monthSpent"] as? Double { monthSpent = v }
        if let v = ctx["monthBudget"] as? Double { monthBudget = v }
        if let v = ctx["savings"] as? Double { savings = v }
        if let v = ctx["budgetableSpent"] as? Double { budgetableSpent = v > 0 ? v : monthSpent }

        if let arr = ctx["recentExpenses"] as? [[String: Any]] {
            recentExpenses = arr.compactMap(parseExpense)
        }
        if let arr = ctx["accounts"] as? [[String: Any]] {
            accounts = arr.compactMap(parseAccount)
        }
        _hasData = true
    }

    private func parseExpense(_ d: [String: Any]) -> WatchExpense? {
        guard let id = d["id"] as? String,
              let amount = (d["amount"] as? NSNumber)?.doubleValue,
              let category = d["category"] as? String else { return nil }
        let note = d["note"] as? String ?? ""
        let type = d["type"] as? String ?? "expense"
        let ts = (d["date"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
        return WatchExpense(id: id, amount: amount, category: category,
                            note: note, type: type, date: Date(timeIntervalSince1970: ts))
    }

    private func parseAccount(_ d: [String: Any]) -> WatchAccount? {
        guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
        return WatchAccount(id: id, name: name)
    }

    // MARK: Add expense (Watch → Phone)

    /// Queues an expense for delivery to the iPhone app via transferUserInfo.
    /// Delivery is guaranteed even when the phone app is backgrounded.
    func addExpense(
        amount: Double,
        category: String,
        note: String,
        accountId: String?,
        completion: @escaping (Bool) -> Void
    ) {
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
        var payload: [String: Any] = [
            "type": "addExpense",
            "amount": amount,
            "category": category,
            "note": note,
        ]
        if let accountId = accountId { payload["accountId"] = accountId }
        session.transferUserInfo(payload)
        syncStatus = .queued
        DispatchQueue.main.async {
            self.sending = false
            self.lastError = nil
            completion(true)
        }
    }

    // MARK: WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            let ctx = session.receivedApplicationContext
            if !ctx.isEmpty { self.applyContext(ctx) }
            if !self._hasData { self.readFromAppGroup() }
            self.syncStatus = self._hasData ? .synced(Date()) : .offline
        }
    }

    /// Receives data pushed by the phone via updateApplicationContext.
    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        DispatchQueue.main.async {
            self.applyContext(applicationContext)
            self.syncStatus = .synced(Date())
        }
    }

    /// Receives direct messages from the phone (e.g. reply to requestSync).
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        DispatchQueue.main.async { self.applyContext(message) }
        replyHandler([:])
    }
}
