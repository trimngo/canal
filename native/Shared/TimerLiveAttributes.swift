#if os(iOS)
import ActivityKit
import Foundation

struct TimerLiveAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var dueAt: Date?
        var pausedRemaining: Double?
        var duration: Double
        var token: String? = nil
        var watchRearmHint: Bool? = nil
        var restartCount: Int? = nil
        var elapsedSeconds: Double? = nil
        var elapsedStartedAt: Date? = nil
    }
    var queueID: String
}
#endif
