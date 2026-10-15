import Foundation

public enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
    case today, week, allTime, custom
    public var id: String { rawValue }
    public var name: String {
        switch self { case .today: return "Today"; case .week: return "Past 7 days"; case .allTime: return "All time"; case .custom: return "Custom" }
    }
}

public struct DailyTotal: Identifiable, Equatable, Sendable {
    public var day: Date
    public var categoryID: String
    public var name: String
    public var minutes: Double
    public var id: String { "\(day.timeIntervalSince1970)-\(categoryID)" }
}

public struct HistoryReport: Sendable {
    public var rows: [BreakdownRow]
    public var dailyTotals: [DailyTotal]
    public var samples: [CheckIn]
    public var start: Date
    public var end: Date
    public var trackedMinutes: Double
    public var remainingMinutes: Double
    public var totalMinutes: Double { trackedMinutes + remainingMinutes }
}

extension Ledger {
    public func history(range: HistoryRange, start: Date = Date(), end: Date = Date(), now: Date = Date(), calendar: Calendar = .current) -> HistoryReport {
        let today = calendar.startOfDay(for: now)
        let lower: Date
        let upper: Date
        switch range {
        case .today: lower = today; upper = now
        case .week: lower = calendar.date(byAdding: .day, value: -6, to: today) ?? today; upper = now
        case .allTime: lower = calendar.startOfDay(for: entries.filter { $0.end <= now }.map(\.end).min() ?? today); upper = now
        case .custom:
            lower = min(today, calendar.startOfDay(for: min(start, end)))
            let last = min(today, calendar.startOfDay(for: max(start, end)))
            upper = min(now, calendar.date(byAdding: .day, value: 1, to: last) ?? now)
        }
        let samples = entries.filter { $0.end >= lower && ($0.end < upper || upper == now && $0.end == now) && $0.end <= now }
        let known = Set(categories.map(\.id))
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        // Visit only days with observations; empty years do not create an
        // unbounded calendar loop, and historical estimates stop at the last log.
        let observations = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.end) }
        let days = observations.keys.sorted()
        var totals: [String: Double] = [:]
        var daily: [DailyTotal] = []
        for day in days {
            var values: [String: Double] = [:]
            var dailyLedger = self; dailyLedger.entries = observations[day] ?? []
            for segment in dailyLedger.inferredSegments(on: day, now: now, calendar: calendar) {
                let id = known.contains(segment.categoryID ?? "") ? segment.categoryID! : "uncategorized"
                let minutes = max(0, min(segment.end, upper).timeIntervalSince(max(segment.start, lower)) / 60)
                values[id, default: 0] += minutes
                totals[id, default: 0] += minutes
            }
            for (id, minutes) in values where minutes > 0 {
                daily.append(DailyTotal(day: day, categoryID: id, name: names[id] ?? "Uncategorized", minutes: minutes))
            }
        }
        let tracked = totals.values.reduce(0, +)
        var remaining = 0.0
        if range == .today, settings.showRemainingTime,
           let bedtime = calendar.date(bySettingHour: settings.bedtimeMinute / 60, minute: settings.bedtimeMinute % 60, second: 0, of: today) {
            remaining = max(0, bedtime.timeIntervalSince(now) / 60)
        }
        var rows = totals.map { id, minutes in
            BreakdownRow(id: id, name: names[id] ?? "Uncategorized", minutes: minutes, dayMinutes: tracked + remaining)
        }.filter { $0.minutes > 0 }
        if remaining > 0 { rows.append(BreakdownRow(id: "remaining", name: "Time remaining", minutes: remaining, dayMinutes: tracked + remaining)) }
        rows.sort { $0.minutes == $1.minutes ? $0.name < $1.name : $0.minutes > $1.minutes }
        return HistoryReport(rows: rows, dailyTotals: daily.sorted { $0.day == $1.day ? $0.categoryID < $1.categoryID : $0.day < $1.day }, samples: samples, start: lower, end: upper, trackedMinutes: tracked, remainingMinutes: remaining)
    }
}
