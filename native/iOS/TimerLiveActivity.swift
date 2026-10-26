import ActivityKit
import UIKit
import LedgerCore

/// Mirrors the shared timer. Explicit controls can move alert ownership to iPhone.
@MainActor
final class TimerLiveActivity {
    static let shared = TimerLiveActivity()
    private var last: TimerLiveAttributes.ContentState?
    private var work: Task<Void, Never>?
    func refresh(_ ledger: Ledger) async {
        let previous = work
        let task = Task { @MainActor in
            _ = await previous?.value
            await self.refreshSerially(ledger)
        }
        work = task; await task.value
    }
    private func refreshSerially(_ ledger: Ledger) async {
        let activities = Activity<TimerLiveAttributes>.activities
        guard let timer = ledger.currentTimer, let control = ledger.timerControl else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            last = nil; return
        }
        let state = TimerLiveAttributes.ContentState(title: timer.title, dueAt: control.dueAt,
            pausedRemaining: control.pausedRemaining, duration: timer.duration, token: control.token)
        let content = ActivityContent(state: state, staleDate: control.dueAt)
        // One Live Activity spans task transitions, including changes received
        // while iOS is backgrounded. Creating a new activity would require foreground.
        if let activity = activities.first {
            if last != state { await activity.update(content); last = state }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled, UIApplication.shared.applicationState == .active {
            do {
                _ = try Activity.request(attributes: TimerLiveAttributes(queueID: "main"), content: content, pushType: nil)
                last = state
            } catch { /* Opening the queue retries; an unavailable mirror cannot stop a Watch timer. */ }
        }
    }
}
