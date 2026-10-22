import Foundation

public enum AllocationSortColumn: String, CaseIterable, Identifiable, Sendable {
    case category, goal, today, week
    public var id: String { rawValue }
}

extension Ledger {
    /// Sort one sibling level, without moving or flattening the categories.
    /// Percentages and hours have the same order within each reporting column.
    public func sortedAllocationCategories(_ categories: [LedgerCategory], by column: AllocationSortColumn, descending: Bool,
                                           goals: [String: Double], today: AllocationPeriod, week: AllocationPeriod) -> [LedgerCategory] {
        var values: [String: Double] = [:]
        for category in categories {
            let value: Double?
            switch column {
            case .category: value = nil
            case .goal: value = goals[category.id]
            case .today: value = today.sufficient ? today.total(for: category.id, ledger: self) : nil
            case .week: value = week.sufficient ? week.total(for: category.id, ledger: self) : nil
            }
            if let value, value.isFinite { values[category.id] = value }
        }
        return sortAllocationCategories(categories, by: column, descending: descending, values: values)
    }
}

extension AllocationCategoryIndex {
    /// The editor has already aggregated these columns once for all rows.
    public func sorted(_ categories: [LedgerCategory], by column: AllocationSortColumn, descending: Bool,
                       goals: [String: Double], todayTotals: [String: Double]?, weekTotals: [String: Double]?) -> [LedgerCategory] {
        let values: [String: Double]
        switch column {
        case .category: values = [:]
        case .goal: values = goals
        case .today: values = todayTotals.map { totals in Dictionary(uniqueKeysWithValues: categories.map { ($0.id, totals[$0.id, default: 0]) }) } ?? [:]
        case .week: values = weekTotals.map { totals in Dictionary(uniqueKeysWithValues: categories.map { ($0.id, totals[$0.id, default: 0]) }) } ?? [:]
        }
        return sortAllocationCategories(categories, by: column, descending: descending, values: values)
    }
}

private func sortAllocationCategories(_ categories: [LedgerCategory], by column: AllocationSortColumn, descending: Bool,
                                      values: [String: Double]) -> [LedgerCategory] {
    let values = values.filter { $0.value.isFinite }
    return categories.sorted { lhs, rhs in
        if column != .category {
            let a = values[lhs.id], b = values[rhs.id]
            // A blank goal is always last; an explicit zero is a value.
            if (a == nil) != (b == nil) { return a != nil }
            if let a, let b, a != b { return descending ? a > b : a < b }
        }
        let names = lhs.name.localizedStandardCompare(rhs.name)
        if names != .orderedSame {
            return column == .category && descending ? names == .orderedDescending : names == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}
