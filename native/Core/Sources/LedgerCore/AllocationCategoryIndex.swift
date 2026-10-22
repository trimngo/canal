import Foundation

/// A read-only index for a category editing session. Reconcile the hierarchy
/// once, rather than rebuilding it for every cell, sort, and typed character.
public struct AllocationCategoryIndex: Sendable {
    public let parents: [String: String]
    public let leafIDs: Set<String>
    private let known: Set<String>
    private let roots: [LedgerCategory]
    private let childGroups: [String: [LedgerCategory]]

    public init(ledger: Ledger = Ledger()) {
        parents = ledger.categoryParents
        known = Set(ledger.categories.map(\.id))
        leafIDs = known.subtracting(parents.values)
        var groups: [String: [LedgerCategory]] = [:], roots: [LedgerCategory] = []
        for category in ledger.categories {
            if let parent = parents[category.id] { groups[parent, default: []].append(category) }
            else { roots.append(category) }
        }
        func ordered(_ categories: [LedgerCategory]) -> [LedgerCategory] {
            categories.sorted {
                if ($0.sortOrder ?? 0) != ($1.sortOrder ?? 0) { return ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
                return $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
        self.roots = ordered(roots)
        childGroups = groups.mapValues(ordered)
    }

    public func children(of parent: String?) -> [LedgerCategory] {
        parent.map { childGroups[$0] ?? [] } ?? roots
    }

    /// Direct shares are carried up once. Sibling shares and direct-to-parent
    /// time retain the same accounting as AllocationPeriod.total(for:ledger:).
    public func totals(_ direct: [String: Double]) -> [String: Double] {
        var result = direct.filter { known.contains($0.key) }
        for (id, amount) in direct where known.contains(id) {
            var node = id
            while let parent = parents[node] {
                result[parent, default: 0] += amount
                node = parent
            }
        }
        return result
    }

    public func goals(_ values: [String: Double]) -> [String: Double] {
        // Match the stable addition order of calculatedAllocationGoals.
        var result = values.filter { leafIDs.contains($0.key) }
        for id in result.keys.sorted() {
            var node = id
            while let parent = parents[node] {
                result[parent, default: 0] += values[id]!
                node = parent
            }
        }
        return result
    }
}
