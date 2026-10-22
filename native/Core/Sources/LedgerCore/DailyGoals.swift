import Foundation

/// A forecast horizon, not a filter on recorded samples or inferred segments.
public struct GoalDayWindow: Equatable, Sendable {
    public let interval: DateInterval
    public let now: Date
    public var minutes: Double { interval.duration / 60 }
    public var remainingMinutes: Double { max(0, interval.end.timeIntervalSince(max(interval.start, now)) / 60) }
    public var elapsedMinutes: Double { minutes - remainingMinutes }
}

public struct DailyGoalProgress: Identifiable, Equatable, Sendable {
    public let category: LedgerCategory
    public let targetMinutes: Double
    public let actualMinutes: Double
    public let depth: Int
    public let isRollup: Bool
    public var id: String { category.id }
    public var remainingMinutes: Double { max(0, targetMinutes - actualMinutes) }
    public var fraction: Double { targetMinutes > 0 ? min(1, actualMinutes / targetMinutes) : 1 }
    public var isMet: Bool { remainingMinutes < 0.0000001 }
}

public struct GoalDayBarSegment: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case elapsed, goal(String), other }
    public let kind: Kind
    public let minutes: Double
    public var id: String {
        switch kind {
        case .elapsed: return "elapsed"
        case .goal(let id): return "goal:\(id)"
        case .other: return "other"
        }
    }
}

public struct DailyGoalsReport: Equatable, Sendable {
    public let window: GoalDayWindow
    public let goals: [DailyGoalProgress]
    public let uncategorizedMinutes: Double
    public var commitments: [DailyGoalProgress] { goals.filter { !$0.isRollup } }
    public var neededMinutes: Double { commitments.reduce(0) { $0 + $1.remainingMinutes } }
    public var otherMinutes: Double { max(0, window.remainingMinutes - neededMinutes) }
    public var shortfallMinutes: Double { max(0, neededMinutes - window.remainingMinutes) }
    /// Every row uses the same ruler, including parent totals. Fill is actual
    /// progress inside this target width, rather than a second normalized bar.
    public var goalScaleMinutes: Double { goals.map(\.targetMinutes).max() ?? 0 }
    public func goalWidthFraction(_ goal: DailyGoalProgress) -> Double {
        goalScaleMinutes > 0 ? goal.targetMinutes / goalScaleMinutes : 0
    }
    /// The entire configured day, never rescaled to just the remaining goals.
    /// Show only what fits after Now; shortfallMinutes reports overflow instead
    /// of shrinking time to make an overfull plan appear feasible.
    public var dayBarSegments: [GoalDayBarSegment] {
        var result: [GoalDayBarSegment] = []
        if window.elapsedMinutes > 0 { result.append(GoalDayBarSegment(kind: .elapsed, minutes: window.elapsedMinutes)) }
        var available = window.remainingMinutes
        for goal in commitments where goal.remainingMinutes > 0 {
            let fitted = min(available, goal.remainingMinutes)
            if fitted > 0 { result.append(GoalDayBarSegment(kind: .goal(goal.id), minutes: fitted)) }
            available -= fitted
        }
        if available > 0 { result.append(GoalDayBarSegment(kind: .other, minutes: available)) }
        return result
    }
}

extension Ledger {
    public func goalDayWindow(on date: Date = Date(), now: Date = Date(), calendar: Calendar = .current) -> GoalDayWindow? {
        let start = settings.startMinute, end = settings.endMinute
        guard (0..<1440).contains(start), (0..<1440).contains(end), end > start else { return nil }
        let cal = reportingCalendar(calendar)
        // Resolve wall-clock times in the reporting zone, rather than adding
        // seconds to midnight (which shifts the window on DST dates).
        guard let from = cal.date(bySettingHour: start / 60, minute: start % 60, second: 0, of: date,
                                  matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              let to = cal.date(bySettingHour: end / 60, minute: end % 60, second: 0, of: date,
                                matchingPolicy: .nextTime, repeatedTimePolicy: .first), to > from else { return nil }
        return GoalDayWindow(interval: DateInterval(start: from, end: to), now: now)
    }

    public func dailyGoals(now: Date = Date(), calendar: Calendar = .current) -> DailyGoalsReport? {
        guard let window = goalDayWindow(on: now, now: now, calendar: calendar) else { return nil }
        // Deliberately no clippingTo: early/late entries still count. Keep the
        // existing midpoint/carry-forward and equal-share category accounting.
        let actual = allocation(on: now, now: now, calendar: calendar)
        let goals = currentGoals(at: now)
        var progress: [DailyGoalProgress] = []
        func append(_ category: LedgerCategory, depth: Int) {
            let children = children(of: category.id)
            if let percentage = goals[category.id], percentage.isFinite, percentage >= 0 {
                progress.append(DailyGoalProgress(category: category, targetMinutes: window.minutes * percentage / 100,
                    actualMinutes: actual.total(for: category.id, ledger: self), depth: depth, isRollup: !children.isEmpty))
            }
            for child in children { append(child, depth: depth + 1) }
        }
        for root in children(of: nil) { append(root, depth: 0) }
        return DailyGoalsReport(window: window, goals: progress,
                                uncategorizedMinutes: actual.directMinutes["uncategorized", default: 0])
    }

    /// Historical averages remain measured from logs; daily goal equivalents
    /// now use the configured window, including before any history exists.
    public func goalAllocationReference(now: Date = Date(), calendar: Calendar = .current) -> AllocationReference {
        var reference = completedAllocationReference(now: now, calendar: calendar)
        reference.goalDayMinutes = goalDayWindow(on: now, now: now, calendar: calendar)?.minutes
        return reference
    }
}
