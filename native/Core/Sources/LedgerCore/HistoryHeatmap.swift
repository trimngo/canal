import Foundation

/// A calendar grid of the existing daily totals. Missing days stay missing;
/// a zero on a represented day means no time in that category.
public struct HistoryHeatmap: Sendable {
    public let days: [Date]
    public let rows: [BreakdownRow]
    public let maximumMinutes: Double
    private let points: [Date: [String: DailyTotal]]

    public init(report: HistoryReport, calendar: Calendar) {
        rows = report.rows
        maximumMinutes = report.dailyTotals.map(\.minutes).max() ?? 0
        points = Dictionary(grouping: report.dailyTotals, by: \.day).mapValues { values in
            Dictionary(values.map { ($0.categoryID, $0) }, uniquingKeysWith: { first, _ in first })
        }
        // A completed custom range ends at the following midnight, exclusively.
        let lastInstant = report.end > report.start ? report.end.addingTimeInterval(-0.001) : report.end
        let last = calendar.startOfDay(for: lastInstant)
        var day = calendar.startOfDay(for: report.start), dates: [Date] = []
        while day <= last {
            dates.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        days = dates
    }

    public func point(on day: Date, categoryID: String) -> DailyTotal? { points[day]?[categoryID] }
}
