import Foundation

public struct DailyComparisonRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let minutes: Double
    public let percent: Double
    public let averageMinutes: Double
    public let averagePercent: Double
    public let unreviewedMinutes: Double
    public var minuteChange: Double { minutes - averageMinutes }
    public var percentagePointChange: Double { percent - averagePercent }
}
public struct DailyComparison: Equatable, Sendable {
    public let day: Date
    public let baselineStart: Date
    public let baselineEnd: Date
    public let representedDays: Int
    public let isToday: Bool
    public let hasData: Bool
    public let rows: [DailyComparisonRow]
}
extension Ledger {
    /// Every selected date has its own earlier baseline. Missing days are gaps,
    /// while a represented day without this category contributes a real zero.
    public func dailyComparison(on date: Date, now: Date = Date(), calendar: Calendar = .current) -> DailyComparison {
        let cal = reportingCalendar(calendar), today = cal.startOfDay(for: now)
        let day = min(cal.startOfDay(for: date), today)
        let lower = cal.date(byAdding: .day, value: -7, to: day)!
        let upper = cal.date(byAdding: .day, value: -1, to: day)!
        let selected = allocation(on: day, now: now, calendar: cal)
        let baseline = (-7 ... -1).compactMap { cal.date(byAdding: .day, value: $0, to: day) }
            .map { allocation(on: $0, now: now, calendar: cal) }.filter { $0.sufficient }
        let ids = Set(selected.directMinutes.keys).union(baseline.flatMap { $0.directMinutes.keys })
        let count = Double(baseline.count)
        let rows = ids.compactMap { id -> DailyComparisonRow? in
            let minutes = selected.directMinutes[id, default: 0]
            let average = count > 0 ? baseline.reduce(0) { $0 + $1.directMinutes[id, default: 0] } / count : 0
            guard minutes > 0 || average > 0 else { return nil }
            let category = categories.first { $0.id == id }
            let name = (category?.name ?? "Uncategorized") + (children(of: id).isEmpty ? "" : " (direct)")
            return DailyComparisonRow(id: id, name: name, minutes: minutes, percent: selected.percent(minutes),
                averageMinutes: average,
                averagePercent: count > 0 ? baseline.reduce(0) { $0 + $1.percent($1.directMinutes[id, default: 0]) } / count : 0,
                unreviewedMinutes: selected.unreviewedDirectMinutes[id, default: 0])
        }.sorted { abs($0.minuteChange) == abs($1.minuteChange) ? $0.name < $1.name : abs($0.minuteChange) > abs($1.minuteChange) }
        return DailyComparison(day: day, baselineStart: lower, baselineEnd: upper, representedDays: baseline.count,
            isToday: day == today, hasData: selected.sufficient, rows: rows)
    }
}
