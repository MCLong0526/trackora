import Foundation
import ActivityKit
import Flutter

/// Manages a Trackora Quick Add Live Activity via a Flutter MethodChannel.
///
/// MethodChannel: `trackora/live_activity`
///   start(Map {currency, todaySpent}) → starts or refreshes the activity
///   update(Map {currency, todaySpent}) → updates ContentState
///   stop                              → ends all Trackora activities
class LiveActivityService {
    private var _activityId: String?

    init(messenger: NSObject & FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "trackora/live_activity",
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard #available(iOS 16.2, *) else {
                // Silently succeed — older iOS just can't show Live Activities.
                result(nil)
                return
            }
            switch call.method {
            case "start":
                self?.startActivity(args: call.arguments, result: result)
            case "update":
                self?.updateActivity(args: call.arguments, result: result)
            case "stop":
                self?.stopAllActivities(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - Private helpers

    @available(iOS 16.2, *)
    private var currentActivity: Activity<TrackoraLiveActivityAttributes>? {
        guard let id = _activityId else {
            // Fall back to any running activity if our stored ID was lost.
            return Activity<TrackoraLiveActivityAttributes>.activities.first
        }
        return Activity<TrackoraLiveActivityAttributes>.activities.first { $0.id == id }
    }

    @available(iOS 16.2, *)
    private func parseState(from args: Any?) -> TrackoraLiveActivityAttributes.ContentState? {
        guard let map = args as? [String: Any] else { return nil }
        let currency = map["currency"] as? String ?? "$"
        let todaySpent = (map["todaySpent"] as? Double) ?? 0.0
        return TrackoraLiveActivityAttributes.ContentState(
            currency: currency,
            todaySpent: todaySpent
        )
    }

    @available(iOS 16.2, *)
    private func startActivity(args: Any?, result: @escaping FlutterResult) {
        // End any existing Trackora activities first (idempotent restart).
        for existing in Activity<TrackoraLiveActivityAttributes>.activities {
            Task { await existing.end(nil, dismissalPolicy: .immediate) }
        }
        _activityId = nil

        guard let state = parseState(from: args) else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing currency/todaySpent", details: nil))
            return
        }

        do {
            let attributes = TrackoraLiveActivityAttributes()
            let content = ActivityContent(state: state, staleDate: nil)
            let activity = try Activity<TrackoraLiveActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            _activityId = activity.id
            print("[LIVE_ACTIVITY] Started: \(activity.id)")
            result(nil) // Return nil so Dart's invokeMethod<void> works correctly
        } catch {
            print("[LIVE_ACTIVITY] Start failed: \(error.localizedDescription)")
            result(FlutterError(
                code: "START_FAILED",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }

    @available(iOS 16.2, *)
    private func updateActivity(args: Any?, result: @escaping FlutterResult) {
        guard let activity = currentActivity else {
            result(nil)
            return
        }
        guard let state = parseState(from: args) else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing currency/todaySpent", details: nil))
            return
        }
        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.update(content)
            print("[LIVE_ACTIVITY] Updated: \(activity.id)")
        }
        result(nil)
    }

    @available(iOS 16.2, *)
    private func stopAllActivities(result: @escaping FlutterResult) {
        _activityId = nil
        let activities = Activity<TrackoraLiveActivityAttributes>.activities
        if activities.isEmpty {
            result(nil)
            return
        }
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        print("[LIVE_ACTIVITY] Stopped all activities")
        result(nil)
    }
}
