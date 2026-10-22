import Foundation

extension Ledger {
    /// Includes ancestors so filtering never detaches a visible child from its
    /// outline. An explicit zero goal still counts as a configured goal.
    public func activeCategoryIDs(in periods: [AllocationPeriod], includingGoals goals: [String: Double] = [:]) -> Set<String> {
        var ids = Set(goals.keys)
        for period in periods {
            ids.formUnion(period.directMinutes.compactMap { $0.value > 0 ? $0.key : nil })
        }
        let parents = categoryParents
        for id in ids {
            var node = id
            while let parent = parents[node] { ids.insert(parent); node = parent }
        }
        return ids
    }
}
