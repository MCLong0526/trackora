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
}
