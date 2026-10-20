import Foundation

extension HistoryReport {
    /// Nil chooses a small initial comparison. An explicit empty selection stays
    /// empty. Filtered-out categories never change the report's denominators.
    public func trendRows(selectedIDs: [String]?) -> [BreakdownRow] {
        guard let selectedIDs else { return Array(rows.prefix(3)) }
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return selectedIDs.filter { seen.insert($0).inserted }.compactMap { byID[$0] }
    }

    public func trendPoints(categoryIDs: [String]) -> [DailyTotal] {
        let ids = Set(categoryIDs)
        return dailyTotals.filter { ids.contains($0.categoryID) }
    }

    /// Use the report's calendar when inspecting a chart date. A missing day
    /// yields no values, rather than selecting a different day or inventing zero.
    public func trendPoints(on date: Date, categoryIDs: [String], calendar: Calendar) -> [DailyTotal] {
        let day = calendar.startOfDay(for: date)
        return trendPoints(categoryIDs: categoryIDs).filter { $0.day == day }
    }

    /// Shared by all category panels so equally tall lines mean equal time.
    public var trendMaximumHours: Double { max(1, dailyTotals.map { $0.minutes / 60 }.max() ?? 0) }
}
