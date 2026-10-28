import Foundation

extension TimerWidgetSnapshot {
    public enum DisplayState: Equatable, Sendable { case ready, running, paused, finished }
    public func displayState(at now: Date) -> DisplayState {
        if pausedRemaining != nil { return .paused }
        guard let dueAt else { return .ready }
        return dueAt > now ? .running : .finished
    }
}

/// A missed reload must not leave a dynamic complication on a never-ending
/// cached timeline. WidgetKit chooses the actual refresh time and budget.
public enum TimerWidgetRefreshPolicy {
    public static func nextRefresh(snapshot: TimerWidgetSnapshot?, at now: Date) -> Date {
        guard let snapshot, snapshot.displayState(at: now) == .running, let due = snapshot.dueAt else {
            return now.addingTimeInterval(30 * 60)
        }
        // The existing expiry entry changes the display at the deadline even
        // when WidgetKit defers a provider reload. Avoid tight refresh loops.
        return min(now.addingTimeInterval(15 * 60), max(now.addingTimeInterval(60), due.addingTimeInterval(1)))
    }
}
