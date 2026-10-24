import ActivityKit
import UIKit
import LedgerCore

/// A display mirror only. The Watch remains responsible for its own alarm.
@MainActor
final class TimerLiveActivity {
    static let shared = TimerLiveActivity()
    private var last: TimerLiveAttributes.ContentState?
    func refresh(_ ledger: Ledger) async {
        let activities = Activity<TimerLiveAttributes>.activities
        guard let timer = ledger.currentTimer, let control = ledger.timerControl else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            last = nil; return
        }
        let state = TimerLiveAttributes.ContentState(title: timer.title, dueAt: control.dueAt,
            pausedRemaining: control.pausedRemaining, duration: timer.duration)
        let content = ActivityContent(state: state, staleDate: control.dueAt)
        for activity in activities where activity.attributes.taskID != timer.id { await activity.end(nil, dismissalPolicy: .immediate) }
        if let activity = activities.first(where: { $0.attributes.taskID == timer.id }) {
            if last != state { await activity.update(content); last = state }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled, UIApplication.shared.applicationState == .active {
            do {
                _ = try Activity.request(attributes: TimerLiveAttributes(taskID: timer.id), content: content, pushType: nil)
                last = state
            } catch { /* Opening the queue retries; an unavailable mirror cannot stop a Watch timer. */ }
        }
    }
}
