import Foundation

public struct AllocationGoalBalance: Equatable, Sendable {
    public var total: Double
    /// Excess of the closest configured descendant goals over their parent.
    public var overages: [String: Double]
    public var missingRootGoals: [String]
    public var isComplete: Bool { abs(total - 100) < 0.0000001 && overages.isEmpty && missingRootGoals.isEmpty }
}

public enum AllocationGoalFeedback: String, Sendable {
    case below, aligned, above
    public init(actual: Double, goal: Double) {
        // Match the one-decimal precision used for displayed actuals.
        let difference = (actual - goal) * 10
        self = abs(difference) < 0.5 ? .aligned : (difference < 0 ? .below : .above)
    }
}

extension Ledger {
    public func currentGoals(at date: Date = Date()) -> [String: Double] {
        let known = Set(categories.map(\.id))
        return (currentBudget(at: date)?.percentages ?? [:]).filter { known.contains($0.key) }
    }

    public func allocationGoalBalance(_ goals: [String: Double]) -> AllocationGoalBalance {
        let parents = categoryParents, roots = children(of: nil).map(\.id)
        var contained: [String: Double] = [:]
        var missing = Set<String>()
        for (id, amount) in goals {
            var node = id, configuredParent: String?
            while let parent = parents[node] {
                if goals[parent] != nil { configuredParent = parent; break }
                node = parent
            }
            if let parent = configuredParent { contained[parent, default: 0] += amount }
            else if parents[id] != nil {
                while let parent = parents[node] { node = parent }
                if goals[node] == nil { missing.insert(node) }
            }
        }
        var overages: [String: Double] = [:]
        for (id, amount) in contained where amount > goals[id, default: 0] + 0.0000001 {
            overages[id] = amount - goals[id, default: 0]
        }
        return AllocationGoalBalance(total: roots.reduce(0) { $0 + goals[$1, default: 0] },
            overages: overages,
            missingRootGoals: missing.sorted())
    }

    /// Incomplete allocations are intentional saved work. Each individual goal
    /// remains valid; balance is reported separately, never silently repaired.
    public mutating func saveAllocationGoals(_ goals: [String: Double], effectiveAt: Date = Date(), writer: String) throws {
        let known = Set(categories.map(\.id))
        guard effectiveAt.timeIntervalSince1970.isFinite, goals.keys.allSatisfy({ known.contains($0) }),
              goals.values.allSatisfy({ $0.isFinite && (0...100).contains($0) }) else { throw PlannerError.invalidBudget }
        let roots = children(of: nil).map(\.id).sorted()
        let previous = currentBudget(at: effectiveAt)
        guard previous?.percentages != goals || previous?.topLevelCategoryIDs != roots else { return }
        let snapshot = TargetBudget(id: UUID().uuidString, effectiveAt: effectiveAt, percentages: goals,
            revision: nextRevision(writer: writer), topLevelCategoryIDs: roots)
        targetBudgets = (targetBudgets ?? []) + [snapshot]
    }

    /// Read the latest goals so finishing one field never overwrites another
    /// field that arrived from sync while the user was typing.
    public mutating func updateAllocationGoal(categoryID: String, percentage: Double?, writer: String) throws {
        guard categories.contains(where: { $0.id == categoryID }) else { throw LedgerError.invalidCategory }
        var goals = currentGoals()
        if let percentage { goals[categoryID] = percentage } else { goals.removeValue(forKey: categoryID) }
        try saveAllocationGoals(goals, writer: writer)
    }

    public func goalPercentage(for id: String, from period: AllocationPeriod) -> Double? {
        guard period.sufficient, categories.contains(where: { $0.id == id }) else { return nil }
        return (period.percent(period.total(for: id, ledger: self)) * 100).rounded() / 100
    }

    /// Round direct activity shares once, then aggregate the tree. This keeps
    /// parent/child totals consistent and a fully categorized baseline at 100%.
    /// Uncategorized retains its share and is never turned into a goal category.
    public func goalsFromAllocation(_ period: AllocationPeriod) -> [String: Double]? {
        guard period.sufficient, period.trackedMinutes.isFinite, period.trackedMinutes > 0 else { return nil }
        let amounts = period.directMinutes.filter { $0.value > 0 }
        let precise = amounts.mapValues { $0 / period.trackedMinutes * 10_000 }
        var units = precise.mapValues { Int($0.rounded(.down)) }
        let order = precise.keys.sorted {
            let a = precise[$0]! - Double(units[$0]!), b = precise[$1]! - Double(units[$1]!)
            return a == b ? $0 < $1 : a > b
        }
        let remainder = max(0, 10_000 - units.values.reduce(0, +))
        for id in order.prefix(remainder) { units[id, default: 0] += 1 }
        return Dictionary(uniqueKeysWithValues: orderedCategories.map { category in
            let ids = [category.id] + descendants(of: category.id).map(\.id)
            return (category.id, Double(ids.reduce(0) { $0 + units[$1, default: 0] }) / 100)
        })
    }
}
