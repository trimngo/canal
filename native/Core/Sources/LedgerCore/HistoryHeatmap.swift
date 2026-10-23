import Foundation

/// Fully expanded headings with a separate grid row for each direct share.
/// Missing days stay missing; zero means no time on a represented day.
public struct HistoryHeatmap: Sendable {
    public let days: [Date]
    public let rows: [HistoryCategoryRow]
    public let maximumMinutes: Double
    private let points: [Date: [String: DailyTotal]]

    public init(report: HistoryReport, ledger: Ledger, calendar: Calendar) {
        let index = AllocationCategoryIndex(ledger: ledger)
        let totals = index.totals(report.directMinutes)
        var outline: [HistoryCategoryRow] = []
        func append(_ category: LedgerCategory, depth: Int) {
            guard totals[category.id, default: 0] > 0 else { return }
            let children = index.children(of: category.id)
            let row = BreakdownRow(id: category.id, name: category.name, minutes: totals[category.id, default: 0], dayMinutes: report.trackedMinutes)
            outline.append(HistoryCategoryRow(row: row, depth: depth, direct: false, hasChildren: !children.isEmpty))
            if !children.isEmpty, let minutes = report.directMinutes[category.id], minutes > 0 {
                let direct = BreakdownRow(id: category.id, name: "\(category.name) (direct)", minutes: minutes, dayMinutes: report.trackedMinutes)
                outline.append(HistoryCategoryRow(row: direct, depth: depth + 1, direct: true, hasChildren: false))
            }
            for child in children { append(child, depth: depth + 1) }
        }
        // Retain the existing top-level order; every active branch is expanded.
        for row in report.rows {
            if let category = index.children(of: nil).first(where: { $0.id == row.id }) { append(category, depth: 0) }
            else if row.id == "uncategorized" {
                outline.append(HistoryCategoryRow(row: row, depth: 0, direct: false, hasChildren: false))
            }
        }
        rows = outline
        let directPoints = Dictionary(grouping: report.directDailyTotals, by: \.day).mapValues { values in
            Dictionary(values.map { ($0.categoryID, $0) }, uniquingKeysWith: { first, _ in first })
        }
        points = directPoints.mapValues { daily in
            Dictionary(uniqueKeysWithValues: outline.filter { !$0.hasChildren }.compactMap { item -> (String, DailyTotal)? in
                guard var point = daily[item.row.id] else { return nil }
                point.categoryID = item.id; point.name = item.row.name
                return (item.id, point)
            })
        }
        maximumMinutes = points.values.flatMap { $0.values }.map(\.minutes).max() ?? 0
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

    /// Use the displayed row ID: direct:<categoryID> for a parent's direct time.
    /// Headings intentionally have no values, preventing duplicate totals.
    public func point(on day: Date, categoryID: String) -> DailyTotal? { points[day]?[categoryID] }
}
