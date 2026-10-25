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
    public var dayMinutes: Double
    public var segmentStart: Date
    public var percent: Double { dayMinutes > 0 ? minutes / dayMinutes * 100 : 0 }
    public var seriesID: String { "\(categoryID)-\(segmentStart.timeIntervalSince1970)" }
    public var id: String { "\(day.timeIntervalSince1970)-\(categoryID)" }
}

public struct HistoryReport: Sendable {
    public var rows: [BreakdownRow]
    public var dailyTotals: [DailyTotal]
    public var samples: [CheckIn]
    public var start: Date
    public var end: Date
    public var trackedMinutes: Double
    /// Direct shares, before rolling descendants into their parents. Kept in
    /// the report so expanding a row never re-estimates or double counts logs.
    public var directMinutes: [String: Double] = [:]
    /// Daily direct shares for the heatmap. The existing dailyTotals retain
    /// their parent rollups for the other charts.
    public var directDailyTotals: [DailyTotal] = []
    public var unreviewedDirectMinutes: [String: Double] = [:]
    public func unreviewed(for id: String, in ledger: Ledger, direct: Bool = false) -> Double {
        if direct { return unreviewedDirectMinutes[id, default: 0] }
        let family = Set([id] + ledger.descendants(of: id).map(\.id))
        return unreviewedDirectMinutes.filter { family.contains($0.key) }.values.reduce(0, +)
    }

    public func categoryOutline(in ledger: Ledger, expanded: Set<String>, hideZeroTime: Bool = false) -> [HistoryCategoryRow] {
        let period = AllocationPeriod(trackedMinutes: trackedMinutes, directMinutes: directMinutes)
        let visible = ledger.activeCategoryIDs(in: [period])
        var result: [HistoryCategoryRow] = []
        func append(_ row: BreakdownRow, depth: Int) {
            guard !hideZeroTime || visible.contains(row.id) else { return }
            let children = ledger.children(of: row.id).filter { !hideZeroTime || visible.contains($0.id) }
            result.append(HistoryCategoryRow(row: row, depth: depth, direct: false, hasChildren: !children.isEmpty))
            guard expanded.contains(row.id), !children.isEmpty else { return }
            if directMinutes[row.id, default: 0] > 0 {
                result.append(HistoryCategoryRow(row: BreakdownRow(id: row.id, name: "Directly in \(row.name)", minutes: directMinutes[row.id, default: 0], dayMinutes: trackedMinutes), depth: depth + 1, direct: true, hasChildren: false))
            }
            for child in children {
                append(BreakdownRow(id: child.id, name: child.name, minutes: period.total(for: child.id, ledger: ledger), dayMinutes: trackedMinutes), depth: depth + 1)
            }
        }
        for row in rows { append(row, depth: 0) }
        if !hideZeroTime {
            let reported = Set(rows.map(\.id))
            for category in ledger.children(of: nil) where !reported.contains(category.id) {
                append(BreakdownRow(id: category.id, name: category.name, minutes: 0, dayMinutes: trackedMinutes), depth: 0)
            }
        }
        return result
    }
}

public struct HistoryCategoryRow: Identifiable, Equatable, Sendable {
    public var row: BreakdownRow
    public var depth: Int
    public var direct: Bool
    public var hasChildren: Bool
    public var id: String { direct ? "direct:\(row.id)" : row.id }
}

extension Ledger {
    public func history(range: HistoryRange, start: Date = Date(), end: Date = Date(), now: Date = Date(), calendar: Calendar = .current, anchor: Date? = nil) -> HistoryReport {
        let cal = reportingCalendar(calendar)
        let today = reportingDay(containing: now, calendar: cal)
        let selectedDay = min(today, cal.startOfDay(for: anchor ?? now))
        let lower: Date
        let last: Date
        switch range {
        case .today: lower = selectedDay; last = selectedDay
        case .week: lower = cal.date(byAdding: .day, value: -6, to: selectedDay) ?? selectedDay; last = selectedDay
        case .allTime:
            lower = activeEntries.filter { $0.end <= now }.map { reportingDay(containing: $0.intervalStart ?? $0.end, calendar: cal) }.min() ?? today
            last = today
        case .custom:
            lower = min(today, cal.startOfDay(for: min(start, end)))
            last = min(today, cal.startOfDay(for: max(start, end)))
        }
        let upper = min(now, dayBounds(on: last, calendar: cal)?.end ?? now)
        // Keep every observation on the selected calendar dates, through now.
        let samples = activeEntries.filter {
            let day = reportingDay(containing: $0.end, calendar: cal)
            if let intervalStart = $0.intervalStart { return intervalStart < upper && $0.end > lower && $0.end <= now }
            return day >= lower && day <= last && $0.end <= now
        }
        let days = activityDays(from: lower, through: upper, calendar: cal).filter { $0 <= last }
        var totals: [String: Double] = [:], daily: [DailyTotal] = []
        var tracked = 0.0, directMinutes: [String: Double] = [:], unreviewed: [String: Double] = [:]
        var periods: [(day: Date, period: AllocationPeriod)] = []
        for day in days {
            let period = allocation(on: day, now: now, calendar: cal)
            guard period.trackedMinutes > 0 else { continue }
            periods.append((day, period))
            tracked += period.trackedMinutes
            for (id, minutes) in period.unreviewedDirectMinutes { unreviewed[id, default: 0] += minutes }
            for (id, minutes) in period.directMinutes { directMinutes[id, default: 0] += minutes }
            for category in children(of: nil) {
                let minutes = period.total(for: category.id, ledger: self)
                if minutes > 0 {
                    totals[category.id, default: 0] += minutes
                }
            }
            let uncategorized = period.directMinutes["uncategorized", default: 0]
            if uncategorized > 0 {
                totals["uncategorized", default: 0] += uncategorized
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
        // Zero means a represented day with no time in this category. A date
        // with no usable logs is a gap, not an invented zero-activity day.
        var previous: Date?, segment = lower
        var directDaily: [DailyTotal] = []
        let directIDs = directMinutes.keys.filter { directMinutes[$0, default: 0] > 0 }.sorted()
        for (day, period) in periods {
            if previous == nil || cal.date(byAdding: .day, value: 1, to: previous!) != day { segment = day }
            for id in directIDs {
                directDaily.append(DailyTotal(day: day, categoryID: id, name: names[id] ?? "Uncategorized",
                    minutes: period.directMinutes[id, default: 0], dayMinutes: period.trackedMinutes, segmentStart: segment))
            }
            for row in rows {
                let minutes = row.id == "uncategorized" ? period.directMinutes[row.id, default: 0] : period.total(for: row.id, ledger: self)
                daily.append(DailyTotal(day: day, categoryID: row.id, name: row.name, minutes: minutes,
                                        dayMinutes: period.trackedMinutes, segmentStart: segment))
            }
            previous = day
        }
        return HistoryReport(rows: rows, dailyTotals: daily, samples: samples, start: lower, end: upper, trackedMinutes: tracked,
                             directMinutes: directMinutes, directDailyTotals: directDaily, unreviewedDirectMinutes: unreviewed)
    }
}
