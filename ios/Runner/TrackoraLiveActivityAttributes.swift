import Foundation
import ActivityKit

/// Shared ActivityKit attributes compiled into both the Runner app (start/update/stop)
/// and the TrackoraWidget extension (render the Live Activity view).
@available(iOS 16.2, *)
struct TrackoraLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currency: String
        var todaySpent: Double
        var todayCount: Int = 0
    }

    // No static fields needed — all display data lives in ContentState.
    init() {}
}
