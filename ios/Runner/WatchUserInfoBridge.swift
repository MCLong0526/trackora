import Flutter
import WatchConnectivity

/// Wraps the watch_connectivity plugin's WCSession delegate to add
/// session(_:didReceiveUserInfo:) support, which the plugin omits.
///
/// The Watch uses WCSession.transferUserInfo() to queue addExpense / requestSync
/// messages when the phone app is not in the foreground. iOS queues them and
/// delivers via didReceiveUserInfo when the app becomes active.
///
/// Received user infos are forwarded to Dart via the `trackora/watch_queue`
/// MethodChannel as invokeMethod("onWatchUserInfo", arguments: userInfo).
final class WatchUserInfoBridge: NSObject, WCSessionDelegate {
    private let original: WCSessionDelegate
    private let channel: FlutterMethodChannel

    init(wrapping original: WCSessionDelegate, channel: FlutterMethodChannel) {
        self.original = original
        self.channel = channel
        super.init()
    }

    // MARK: – Required WCSessionDelegate methods (iOS phone side)
    // These are required on iPhone; call directly without optional chaining.

    func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        original.session(session, activationDidCompleteWith: state, error: error)
        // Notify Dart so it can push the latest context to the Watch.
        // This ensures the Watch gets fresh data even if the dashboard
        // hadn't built yet when the session first activated.
        if state == .activated {
            DispatchQueue.main.async {
                self.channel.invokeMethod("onSessionActivated", arguments: nil)
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        original.sessionDidBecomeInactive(session)
    }

    func sessionDidDeactivate(_ session: WCSession) {
        original.sessionDidDeactivate(session)
    }

    // MARK: – Optional WCSessionDelegate forwarding

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        original.session?(session, didReceiveMessage: message)
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        original.session?(session, didReceiveApplicationContext: applicationContext)
    }

    // MARK: – New: handle transferUserInfo queued from Watch

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let type = userInfo["type"] as? String ?? "unknown"
        print("[PHONE_SYNC] didReceiveUserInfo from Watch: type=\(type)")
        DispatchQueue.main.async {
            self.channel.invokeMethod("onWatchUserInfo", arguments: userInfo)
        }
    }

    // MARK: – Handle sendMessage with replyHandler (Watch Sync button)
    // The watch_connectivity plugin's messageStream doesn't support reply handlers.
    // For requestSync we reply immediately with the last applicationContext the phone
    // pushed (which contains the full dashboard snapshot), so the Watch Sync button
    // gets up-to-date stats without a round-trip async reply.
    // For any other message type we forward to the original plugin delegate.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let type = message["type"] as? String
        if type == "requestSync" {
            print("[PHONE_SYNC] requestSync via sendMessage — replying with applicationContext")
            replyHandler(session.applicationContext)
            return
        }
        original.session?(session, didReceiveMessage: message, replyHandler: replyHandler)
    }
}
