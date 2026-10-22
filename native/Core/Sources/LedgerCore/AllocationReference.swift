import Foundation

/// A recorded-day reference, never a wake/sleep window or a filter on samples.
public struct AllocationReference: Equatable, Sendable {
    public var period: AllocationPeriod
    public init(period: AllocationPeriod = AllocationPeriod()) { self.period = period }
    public var averageDayMinutes: Double? {
        guard period.sufficient, period.trackedMinutes.isFinite, period.trackedMinutes > 0 else { return nil }
        return period.trackedMinutes / Double(period.representedDays)
    }
    public func dailyMinutes(for percentage: Double) -> Double? {
        guard percentage.isFinite, percentage >= 0, let averageDayMinutes else { return nil }
        return averageDayMinutes * percentage / 100
    }
    public func percentage(forDailyHours hours: Double) -> Double? {
        guard hours.isFinite, hours >= 0, let averageDayMinutes else { return nil }
        return hours * 60 / averageDayMinutes * 100
    }
    public func averageMinutes(_ minutes: Double) -> Double? {
        guard period.sufficient, minutes.isFinite, minutes >= 0 else { return nil }
        return minutes / Double(period.representedDays)
    }
}

public struct AllocationCapacity: Equatable, Sendable {
    public var goalsPercentage: Double
    public var otherPercentage: Double?
    public var roomPercentage: Double? { otherPercentage.map { 100 - goalsPercentage - $0 } }
}

extension Ledger {
    /// Previous seven local calendar dates, excluding unfinished today. Missing
    /// dates are excluded, reported by representedDays, never invented as zero.
    public func completedAllocationReference(now: Date = Date(), calendar: Calendar = .current) -> AllocationReference {
        let cal = reportingCalendar(calendar), today = reportingDay(containing: now, calendar: cal)
        var result = AllocationPeriod(); result.requestedDays = 7
        for offset in -7 ... -1 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let period = allocation(on: day, now: now, calendar: cal)
            result.trackedMinutes += period.trackedMinutes; result.representedDays += period.representedDays
            for (id, minutes) in period.directMinutes { result.directMinutes[id, default: 0] += minutes }
        }
        return AllocationReference(period: result)
    }

    public func allocationCapacity(goals: [String: Double], reference: AllocationReference) -> AllocationCapacity {
        let parents = Set(categoryParents.values), known = Set(categories.map(\.id))
        let editable = goals.filter { known.contains($0.key) && !parents.contains($0.key) }
        let total = allocationGoalBalance(editable).total
        guard reference.period.sufficient else { return AllocationCapacity(goalsPercentage: total, otherPercentage: nil) }
        // Direct-to-parent and Uncategorized shares have no own editable goal.
        // Each measured share is counted once; calculated parent totals do not
        // exclude their unplanned children or Direct time from this estimate.
        let other = reference.period.directMinutes.filter { editable[$0.key] == nil }.values.reduce(0, +)
        return AllocationCapacity(goalsPercentage: total, otherPercentage: reference.period.percent(other))
    }
}
