import Foundation

public enum HistoryRange: String, CaseIterable, Identifiable, Hashable, Sendable {
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
        let cal = reportingCalendar(calendar)
        let today = wakingDay(containing: now, calendar: cal)
        let lower: Date
        let last: Date
        switch range {
        case .today: lower = today; last = today
        case .week: lower = cal.date(byAdding: .day, value: -6, to: today) ?? today; last = today
        case .allTime:
            lower = activeEntries.filter { $0.end <= now }.map { wakingDay(containing: $0.end, calendar: cal) }.min() ?? today
            last = today
        case .custom:
            lower = min(today, cal.startOfDay(for: min(start, end)))
            last = min(today, cal.startOfDay(for: max(start, end)))
        }
        let upper = min(now, wakingBounds(on: last, calendar: cal)?.end ?? now)
        // The log list retains even observations outside the configured schedule.
        let samples = activeEntries.filter {
            let day = wakingDay(containing: $0.end, calendar: cal)
            return day >= lower && day <= last && $0.end <= now
        }
        let days = Set(samples.map { wakingDay(containing: $0.end, calendar: cal) }).sorted()
        var totals: [String: Double] = [:], daily: [DailyTotal] = []
        var tracked = 0.0
        for day in days {
            let period = allocation(on: day, now: now, calendar: cal)
            tracked += period.wakingMinutes
            for category in children(of: nil) {
                let minutes = period.total(for: category.id, ledger: self)
                if minutes > 0 {
                    totals[category.id, default: 0] += minutes
                    daily.append(DailyTotal(day: day, categoryID: category.id, name: category.name, minutes: minutes))
                }
            }
            let uncategorized = period.directMinutes["uncategorized", default: 0]
            if uncategorized > 0 {
                totals["uncategorized", default: 0] += uncategorized
                daily.append(DailyTotal(day: day, categoryID: "uncategorized", name: "Uncategorized", minutes: uncategorized))
            }
        }
        let names = Dictionary(categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var rows: [BreakdownRow] = []
        for (id, minutes) in totals {
            rows.append(BreakdownRow(id: id, name: names[id] ?? "Uncategorized", minutes: minutes, dayMinutes: tracked))
        }
        rows.sort { lhs, rhs in
            if lhs.minutes == rhs.minutes { return lhs.name < rhs.name }
            return lhs.minutes > rhs.minutes
        }
        return HistoryReport(rows: rows, dailyTotals: daily, samples: samples, start: lower, end: upper, trackedMinutes: tracked, remainingMinutes: 0)
    }
}
