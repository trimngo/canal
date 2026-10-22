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
    public var id: String { category.id }
    public var remainingMinutes: Double { max(0, targetMinutes - actualMinutes) }
    public var fraction: Double { targetMinutes > 0 ? min(1, actualMinutes / targetMinutes) : 1 }
    public var isMet: Bool { remainingMinutes < 0.0000001 }
}

public struct DailyGoalsReport: Equatable, Sendable {
    public let window: GoalDayWindow
    public let goals: [DailyGoalProgress]
    public let uncategorizedMinutes: Double
    public var neededMinutes: Double { goals.reduce(0) { $0 + $1.remainingMinutes } }
    public var otherMinutes: Double { max(0, window.remainingMinutes - neededMinutes) }
    public var shortfallMinutes: Double { max(0, neededMinutes - window.remainingMinutes) }
    /// A common scale for the remaining-goal segments and the unassigned space.
    /// When over capacity, the amount beyond the clock time remains explicit.
    public var barMinutes: Double { max(window.remainingMinutes, neededMinutes) }
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
        let goals = editableAllocationGoals(at: now)
        // Parents sum their leaves. Listing leaves only means neither time nor
        // required effort is counted again through a calculated parent goal.
        let progress = orderedCategories.compactMap { category -> DailyGoalProgress? in
            guard let percentage = goals[category.id], percentage.isFinite, percentage > 0 else { return nil }
            return DailyGoalProgress(category: category, targetMinutes: window.minutes * percentage / 100,
                                     actualMinutes: actual.total(for: category.id, ledger: self))
        }
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
