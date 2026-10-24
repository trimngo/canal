import Foundation

public struct InboxCategorySummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let depth: Int
    /// All saved items, matching the category search (including other lists).
    public let count: Int
    public let topRanked: Capture?
    public let overallRank: Int?
}

extension Ledger {
    /// A frozen, newest-first queue. Categorization is independent of review
    /// status and includes completed, reference and snoozed ideas when requested.
    public func inboxCategorizationIDs(uncategorizedOnly: Bool) -> [String] {
        captures.filter { $0.deletedAt == nil && (!uncategorizedOnly || categoryIDs(for: $0).isEmpty || $0.categorySuggestion != nil) }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }.map(\.id)
    }

    /// Use the existing overall ranking, never invent an order for the backlog.
    /// A multi-category item counts once within each parent branch.
    public func inboxCategorySummaries(ranked: [Capture]) -> [InboxCategorySummary] {
        let index = AllocationCategoryIndex(ledger: self)
        var members: [String: Set<String>] = [:], counts: [String: Int] = [:]
        for capture in captures where capture.deletedAt == nil {
            let assigned = categoryIDs(for: capture)
            var family = Set(assigned)
            if family.isEmpty { family.insert("uncategorized") }
            for id in assigned {
                var node = id
                while let parent = index.parents[node] { family.insert(parent); node = parent }
            }
            members[capture.id] = family
            for id in family { counts[id, default: 0] += 1 }
        }
        var first: [String: (Capture, Int)] = [:]
        for (rank, capture) in ranked.enumerated() {
            for id in members[capture.id] ?? [] where first[id] == nil { first[id] = (capture, rank + 1) }
        }
        var rows: [InboxCategorySummary] = []
        func append(_ category: LedgerCategory, depth: Int) {
            guard let count = counts[category.id], count > 0 else { return }
            rows.append(InboxCategorySummary(id: category.id, name: category.name, depth: depth, count: count,
                topRanked: first[category.id]?.0, overallRank: first[category.id]?.1))
            for child in index.children(of: category.id) { append(child, depth: depth + 1) }
        }
        for root in index.children(of: nil) { append(root, depth: 0) }
        if let count = counts["uncategorized"], count > 0 {
            rows.append(InboxCategorySummary(id: "uncategorized", name: "Uncategorized", depth: 0, count: count,
                topRanked: first["uncategorized"]?.0, overallRank: first["uncategorized"]?.1))
        }
        return rows
    }
}
