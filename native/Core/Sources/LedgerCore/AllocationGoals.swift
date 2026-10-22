import Foundation

public struct AllocationGoalBalance: Equatable, Sendable {
    public var total: Double
    public var isComplete: Bool { abs(total - 100) < 0.0000001 }
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
    /// Existing snapshots stay untouched. Only goals on current leaf categories
    /// are editable; old independently entered parent values remain in history.
    public func editableAllocationGoals(at date: Date = Date()) -> [String: Double] {
        let budget = currentBudget(at: date)
        let values = budget?.leafGoalPercentages ?? budget?.percentages ?? [:]
        let parents = Set(categoryParents.values)
        let leaves = Set(categories.map(\.id)).subtracting(parents)
        return values.filter { leaves.contains($0.key) }
    }

    /// Each editable goal contributes once through its ancestors. Direct logs
    /// affect actual time only and never introduce another goal.
    public func calculatedAllocationGoals(_ values: [String: Double]) -> [String: Double] {
        let links = categoryParents
        let parents = Set(links.values)
        let known = Set(categories.map(\.id))
        var goals = values.filter { known.contains($0.key) && !parents.contains($0.key) }
        let leafGoals = goals
        // Stable addition order keeps snapshots/no-op writes deterministic.
        for id in leafGoals.keys.sorted() {
            var node = id
            while let parent = links[node] {
                goals[parent, default: 0] += leafGoals[id]!
                node = parent
            }
        }
        return goals
    }

    public func currentGoals(at date: Date = Date()) -> [String: Double] {
        calculatedAllocationGoals(editableAllocationGoals(at: date))
    }

    public func allocationGoalBalance(_ goals: [String: Double]) -> AllocationGoalBalance {
        let totals = calculatedAllocationGoals(goals)
        return AllocationGoalBalance(total: children(of: nil).reduce(0) { $0 + totals[$1.id, default: 0] })
    }

    /// Incomplete allocations are intentional saved work. Each individual goal
    /// remains valid; balance is reported separately, never silently repaired.
    public mutating func saveAllocationGoals(_ goals: [String: Double], effectiveAt: Date = Date(), writer: String) throws {
        let known = Set(categories.map(\.id)), parents = Set(categoryParents.values)
        guard effectiveAt.timeIntervalSince1970.isFinite, goals.keys.allSatisfy({ known.contains($0) }),
              goals.allSatisfy({ $0.value.isFinite && $0.value >= 0 && (parents.contains($0.key) || $0.value <= 100) }) else { throw PlannerError.invalidBudget }
        let leaves = goals.filter { !parents.contains($0.key) }
        let calculated = calculatedAllocationGoals(leaves)
        let roots = children(of: nil).map(\.id).sorted()
        let previous = currentBudget(at: effectiveAt)
        guard previous?.leafGoalPercentages != leaves || previous?.percentages != calculated || previous?.topLevelCategoryIDs != roots else { return }
        let snapshot = TargetBudget(id: UUID().uuidString, effectiveAt: effectiveAt, percentages: calculated,
            revision: nextRevision(writer: writer), topLevelCategoryIDs: roots, leafGoalPercentages: leaves)
        targetBudgets = (targetBudgets ?? []) + [snapshot]
    }

    /// Read the latest goals so finishing one field never overwrites another
    /// field that arrived from sync while the user was typing.
    public mutating func updateAllocationGoal(categoryID: String, percentage: Double?, writer: String) throws {
        guard categories.contains(where: { $0.id == categoryID }) else { throw LedgerError.invalidCategory }
        guard children(of: categoryID).isEmpty else { throw PlannerError.calculatedGoal }
        var goals = editableAllocationGoals()
        if let percentage { goals[categoryID] = percentage } else { goals.removeValue(forKey: categoryID) }
        try saveAllocationGoals(goals, writer: writer)
    }

    public func goalPercentage(for id: String, from period: AllocationPeriod) -> Double? {
        guard period.sufficient, categories.contains(where: { $0.id == id }), children(of: id).isEmpty else { return nil }
        return (period.percent(period.total(for: id, ledger: self)) * 100).rounded() / 100
    }

    /// Copy measured leaf shares without allocating Direct or Uncategorized time
    /// to goals. Round all measured shares once, then sum leaf goals up the tree.
    /// Do not redistribute the unallocated share among the children.
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
        let parents = Set(categoryParents.values)
        let leaves = Dictionary(uniqueKeysWithValues: categories.filter { !parents.contains($0.id) }.map {
            ($0.id, Double(units[$0.id, default: 0]) / 100)
        })
        return calculatedAllocationGoals(leaves)
    }
}
