import Foundation

/// One independently editable weekly minimum per category. Removed records stay
/// in backups and sync as tombstones, so an older Watch cannot resurrect them.
public struct WeeklyCommitment: Codable, Identifiable, Equatable, Sendable {
    public var id: String { categoryID }
    public var categoryID: String
    public var minimumMinutes: Int
    public var deleted: Bool
    public var revision: Revision
}

public enum CommitmentError: LocalizedError {
    case invalidMinimum
    public var errorDescription: String? { "Enter a weekly minimum greater than zero, up to 168 hours." }
}

public struct CommitmentProgress: Identifiable, Equatable, Sendable {
    public var id: String { commitment.id }
    public var commitment: WeeklyCommitment
    public var name: String
    public var minutes: Double
    public var remainingMinutes: Double { max(0, Double(commitment.minimumMinutes) - minutes) }
    public var isMet: Bool { minutes >= Double(commitment.minimumMinutes) }
}

public struct CommitmentWeek: Sendable {
    public var interval: DateInterval
    public var loggedMinutes: Double
    public var rows: [CommitmentProgress]
}

extension Ledger {
    public var activeWeeklyCommitments: [WeeklyCommitment] {
        let known = Set(categories.map(\.id))
        return (weeklyCommitments ?? []).filter { !$0.deleted && known.contains($0.categoryID) }
    }

    /// Nil removes only the commitment; observations and categories are untouched.
    public mutating func saveWeeklyCommitment(categoryID: String, minimumMinutes: Int?, writer: String) throws {
        if let minutes = minimumMinutes {
            guard categories.contains(where: { $0.id == categoryID }) else { throw LedgerError.invalidCategory }
            guard (1...10080).contains(minutes) else { throw CommitmentError.invalidMinimum }
        }
        let old = weeklyCommitments?.first { $0.id == categoryID }
        guard let value = minimumMinutes ?? old?.minimumMinutes else { return }
        if let old, old.deleted == (minimumMinutes == nil), minimumMinutes == nil || old.minimumMinutes == minimumMinutes { return }
        let item = WeeklyCommitment(categoryID: categoryID, minimumMinutes: value,
                                    deleted: minimumMinutes == nil, revision: nextRevision(writer: writer))
        weeklyCommitments = (weeklyCommitments ?? []).filter { $0.id != categoryID } + [item]
    }

    /// Fixed Monday–Sunday calendar weeks in the reporting time zone. Calendar
    /// arithmetic preserves DST, rather than assuming every week is 168 hours.
    public func commitmentWeek(now: Date = Date(), calendar: Calendar = .current) -> CommitmentWeek {
        var cal = reportingCalendar(calendar)
        cal.firstWeekday = 2; cal.minimumDaysInFirstWeek = 4
        let week = cal.dateInterval(of: .weekOfYear, for: now)!
        let cutoff = DateInterval(start: week.start, end: min(now, week.end))
        var totals = AllocationPeriod()
        var day = week.start
        let last = cal.startOfDay(for: now)
        while day <= last {
            let period = allocation(on: day, now: now, calendar: cal, clippingTo: cutoff)
            totals.trackedMinutes += period.trackedMinutes
            for (id, minutes) in period.directMinutes { totals.directMinutes[id, default: 0] += minutes }
            guard let next = cal.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        let commitments = Dictionary(activeWeeklyCommitments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = orderedCategories.compactMap { category -> CommitmentProgress? in
            guard let commitment = commitments[category.id] else { return nil }
            return CommitmentProgress(commitment: commitment, name: categoryPath(category.id), minutes: totals.total(for: category.id, ledger: self))
        }
        return CommitmentWeek(interval: week, loggedMinutes: totals.trackedMinutes, rows: rows)
    }
}
