import ActivityKit
import UIKit
import LedgerCore

/// Mirrors the shared timer. Explicit controls can move alert ownership to iPhone.
@MainActor
final class TimerLiveActivity {
    static let shared = TimerLiveActivity()
    private var last: TimerLiveAttributes.ContentState?
    private var work: Task<Void, Never>?
    private var pending: Ledger?
    private var backgroundID = UIBackgroundTaskIdentifier.invalid
    private var backgroundGeneration = UUID()
    func refresh(_ ledger: Ledger) async {
        // Keep only the newest pending state while ActivityKit is updating.
        // Rapid Watch actions must not build a queue of obsolete countdowns.
        pending = ledger
        if let work {
            beginBackgroundWork()
            await work.value
            return
        }
        let task = Task { @MainActor in
            self.beginBackgroundWork()
            defer { self.work = nil; self.endBackgroundWork() }
            while !Task.isCancelled, let latest = self.pending {
                self.pending = nil
                await self.refreshSerially(latest)
            }
        }
        work = task; await task.value
    }
    private func beginBackgroundWork() {
        guard backgroundID == .invalid, UIApplication.shared.applicationState != .active else { return }
        let generation = UUID(); backgroundGeneration = generation
        backgroundID = UIApplication.shared.beginBackgroundTask(withName: "Timer Live Activity") { [weak self] in
            Task { @MainActor in
                guard let self, self.backgroundGeneration == generation else { return }
                self.work?.cancel()
                self.endBackgroundWork()
            }
        }
    }
    private func endBackgroundWork() {
        let identifier = backgroundID
        backgroundID = .invalid; backgroundGeneration = UUID()
        if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
    }
    private func refreshSerially(_ ledger: Ledger) async {
        let activities = Activity<TimerLiveAttributes>.activities
        guard let timer = ledger.currentTimer, let control = ledger.timerControl else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            last = nil; return
        }
        let state = TimerLiveAttributes.ContentState(title: timer.title, dueAt: control.dueAt,
            pausedRemaining: control.pausedRemaining, duration: timer.duration, token: control.token,
            watchRearmHint: control.isRemoteWatchRestart)
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
