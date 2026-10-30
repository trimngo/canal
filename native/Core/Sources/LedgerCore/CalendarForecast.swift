import Foundation

/// A transient guess for a calendar event, never a saved log or confirmation.
public struct CategorizedCalendarEvent: Identifiable, Equatable, Sendable {
    public var snapshot: CalendarEventSnapshot
    public var categoryIDs: [String]
    public var id: String { snapshot.id }
    public init(snapshot: CalendarEventSnapshot, categoryIDs: [String] = []) {
        self.snapshot = snapshot; self.categoryIDs = categoryIDs
    }
}

public struct CalendarDayForecast: Equatable, Sendable {
    public let start: Date
    public let end: Date
    /// Occurrences clipped to the remaining part of the reporting day.
    public let events: [CategorizedCalendarEvent]
    public let directMinutes: [String: Double]
    public var minutes: Double { directMinutes.values.reduce(0, +) }
    public func minutes(for categoryID: String, in ledger: Ledger, direct: Bool = false) -> Double {
        if direct { return directMinutes[categoryID, default: 0] }
        return AllocationPeriod(directMinutes: directMinutes).total(for: categoryID, ledger: ledger)
    }

    /// View-only projection for Breakdown/Pie. Actual history, daily trends,
    /// goals and ledger entries continue using the original report.
    public func preview(of actual: HistoryReport, in ledger: Ledger) -> HistoryReport {
        guard minutes > 0 else { return actual }
        var result = actual
        for (id, value) in directMinutes { result.directMinutes[id, default: 0] += value }
        result.trackedMinutes += minutes
        let period = AllocationPeriod(trackedMinutes: result.trackedMinutes, directMinutes: result.directMinutes)
        result.rows = ledger.children(of: nil).filter { $0.id != "uncategorized" }.compactMap { category in
            let value = period.total(for: category.id, ledger: ledger)
            return value > 0 ? BreakdownRow(id: category.id, name: category.name, minutes: value, dayMinutes: result.trackedMinutes) : nil
        }
        if let value = result.directMinutes["uncategorized"], value > 0 {
            result.rows.append(BreakdownRow(id: "uncategorized", name: "Uncategorized", minutes: value, dayMinutes: result.trackedMinutes))
        }
        result.rows.sort { $0.minutes == $1.minutes ? $0.name < $1.name : $0.minutes > $1.minutes }
        return result
    }
}

extension Ledger {
    public func calendarForecast(_ input: [CategorizedCalendarEvent], on day: Date, now: Date = Date(),
                                 calendar: Calendar = .current) -> CalendarDayForecast {
        guard day.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite,
              let bounds = dayBounds(on: day, calendar: calendar) else {
            return CalendarDayForecast(start: .distantPast, end: .distantPast, events: [], directMinutes: [:])
        }
        let lower = max(now, bounds.start)
        let decided = Set((calendarEvents ?? []).filter { $0.decision != .pending }.map(\.id))
        let known = Set(categories.map(\.id))
        var seen = Set<String>(), events: [CategorizedCalendarEvent] = []
        // EventKit can return copies of one occurrence from shared calendars.
        // Deterministic ordering and occurrence identity prevent double counting.
        for var event in input.sorted(by: {
            ($0.id, $0.snapshot.calendarID, $0.snapshot.title) < ($1.id, $1.snapshot.calendarID, $1.snapshot.title)
        }) {
            let snapshot = event.snapshot
            guard lower < bounds.end, !decided.contains(event.id), !seen.contains(event.id),
                  snapshot.start.timeIntervalSince1970.isFinite, snapshot.end.timeIntervalSince1970.isFinite,
                  snapshot.end > snapshot.start else { continue }
            let start = max(lower, snapshot.start), end = min(bounds.end, snapshot.end)
            guard end > start else { continue }
            seen.insert(event.id)
            let chosen = calendarEvents?.first { $0.id == event.id }?.plannedCategoryIDs
            let raw = Set(chosen ?? event.categoryIDs), valid = raw.filter { known.contains($0) }.sorted()
            // Match log accounting: prefer children, and preserve a missing
            // category's share as Uncategorized after a concurrent deletion.
            let specific = valid.filter { id in
                !valid.contains { other in other != id && descendants(of: id).contains { $0.id == other } }
            }
            let ids = specific + raw.filter { !known.contains($0) }.sorted().map { _ in "uncategorized" }
            event.categoryIDs = ids.isEmpty ? ["uncategorized"] : ids
            event.snapshot.start = start; event.snapshot.end = end
            events.append(event)
        }
        events.sort { $0.snapshot.start == $1.snapshot.start ? $0.id < $1.id : $0.snapshot.start < $1.snapshot.start }
        let boundaries = Set(events.flatMap { [$0.snapshot.start, $0.snapshot.end] }).sorted()
        var direct: [String: Double] = [:]
        for (start, end) in zip(boundaries, boundaries.dropFirst()) where end > start {
            let active = events.filter { $0.snapshot.start < end && $0.snapshot.end > start }
            guard !active.isEmpty else { continue }
            let share = end.timeIntervalSince(start) / 60 / Double(active.count)
            for event in active {
                for id in event.categoryIDs { direct[id, default: 0] += share / Double(event.categoryIDs.count) }
            }
        }
        return CalendarDayForecast(start: bounds.start, end: bounds.end, events: events, directMinutes: direct)
    }
}
