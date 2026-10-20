import Foundation

/// Session-only undo. Persisted category and budget changes use existing
/// revisions, tombstones, sync, and backup formats.
public struct CategoryMoveUndo: Equatable, Sendable {
    public let before: [LedgerCategory]
    public let after: [LedgerCategory]
    public let previousTargets: [String: Double]
    public let resultingTargets: [String: Double]
    public let resultingBudgetID: String?
    public let createdParentID: String?
    public let movedIDs: [String]
}

extension Ledger {
    /// Move whole subtrees in one transaction. Selecting a parent also carries
    /// its descendants, so a selected child is not moved a second time.
    @discardableResult
    public mutating func groupCategories(_ selected: [String], under parent: String?, newParentName: String? = nil, writer: String) throws -> CategoryMoveUndo {
        let known = Set(categories.map(\.id)), selection = Set(selected)
        guard !selection.isEmpty, selection.isSubset(of: known), parent == nil || known.contains(parent!),
              newParentName == nil || parent == nil else { throw PlannerError.invalidHierarchy }
        let moving = orderedCategories.filter { category in
            selection.contains(category.id) && !selection.contains { other in
                other != category.id && descendants(of: other).contains { $0.id == category.id }
            }
        }.map(\.id)
        if let parent {
            guard !moving.contains(where: { $0 == parent || descendants(of: $0).contains { $0.id == parent } }) else { throw PlannerError.invalidHierarchy }
        }
        let before = categories, oldTargets = currentTargets()
        var draft = self, destination = parent, created: String?
        if let name = newParentName {
            try draft.saveCategory(id: nil, name: name, writer: writer)
            created = draft.categories.last!.id; destination = created
        }
        let order = (draft.children(of: destination).compactMap(\.sortOrder).max() ?? 0) + 1
        for (offset, id) in moving.enumerated() {
            guard let index = draft.categories.firstIndex(where: { $0.id == id }) else { continue }
            draft.categories[index].parentID = destination
            draft.categories[index].sortOrder = order + offset
            draft.categories[index].revision = draft.nextRevision(writer: writer)
        }
        try validateNewCategoryConflicts(in: draft)

        // A structural merge combines the selected root goals under the
        // destination root. It never changes unrelated goals or old snapshots.
        var targets = oldTargets
        if var root = destination {
            while let ancestor = draft.categoryParents[root] { root = ancestor }
            for id in moving where categoryParents[id] == nil && id != root {
                if let share = targets.removeValue(forKey: id) { targets[root, default: 0] += share }
            }
        }
        if targets != oldTargets { try draft.saveTargets(targets, writer: writer) }
        let undo = CategoryMoveUndo(before: before, after: draft.categories, previousTargets: oldTargets,
                                    resultingTargets: targets, resultingBudgetID: draft.currentBudget()?.id,
                                    createdParentID: created, movedIDs: moving)
        self = draft
        return undo
    }

    /// Reject only newly introduced conflicts; unrelated old cloud conflicts
    /// must not prevent organizing the rest of the tree.
    private func validateNewCategoryConflicts(in draft: Ledger) throws {
        let known = Set(categories.map(\.id))
        // Repeated logs normally have the same handful of label combinations.
        // Check each combination once, with each ancestry map built once.
        let logSelections = activeEntries.filter { $0.categoryAssignment != .automatic }.map {
            Array(Set($0.categoryIDs ?? $0.categoryID.map { [$0] } ?? []).intersection(known)).sorted()
        }
        let selections = Set(logSelections + captures.filter { $0.deletedAt == nil }.map {
            Array(Set($0.categoryIDs ?? []).intersection(known)).sorted()
        }).filter { $0.count > 1 }
        let oldParents = categoryParents, newParents = draft.categoryParents
        func conflicts(_ a: String, _ b: String, parents: [String: String]) -> Bool {
            func ancestor(_ a: String, of b: String) -> Bool {
                var node = b
                while let parent = parents[node] { if parent == a { return true }; node = parent }
                return false
            }
            return a != b && (ancestor(a, of: b) || ancestor(b, of: a))
        }
        for ids in selections {
            for (index, id) in ids.enumerated() {
                for other in ids.dropFirst(index + 1) {
                    if conflicts(id, other, parents: newParents) && !conflicts(id, other, parents: oldParents) {
                        throw PlannerError.conflictingCategories
                    }
                }
            }
        }
    }

    public func canUndoCategoryMove(_ undo: CategoryMoveUndo) -> Bool {
        // A no-op cloud merge sorts the serialized array by ID. Ordering in the
        // array is not an edit; sortOrder is the persisted display order.
        guard categories.sorted(by: { $0.id < $1.id }) == undo.after.sorted(by: { $0.id < $1.id }),
              currentBudget()?.id == undo.resultingBudgetID else { return false }
        if let id = undo.createdParentID {
            guard !entries.contains(where: { ($0.categoryIDs ?? $0.categoryID.map { [$0] } ?? []).contains(id) }),
                  !captures.contains(where: { ($0.categoryIDs ?? []).contains(id) }) else { return false }
        }
        return true
    }

    public mutating func undoCategoryMove(_ undo: CategoryMoveUndo, writer: String) throws {
        guard canUndoCategoryMove(undo) else { throw AllocationPlanError.staleUndo }
        var draft = self
        for category in undo.before {
            guard let index = draft.categories.firstIndex(where: { $0.id == category.id }), draft.categories[index] != category else { continue }
            var restored = category
            restored.revision = draft.nextRevision(writer: writer)
            draft.categories[index] = restored
        }
        if let id = undo.createdParentID {
            let deletion = GroupDeletion(id: id, automaticRole: nil, revision: draft.nextRevision(writer: writer))
            draft.categories.removeAll { $0.id == id }
            draft.groupDeletions = (draft.groupDeletions ?? []) + [deletion]
        }
        try validateNewCategoryConflicts(in: draft)
        if undo.previousTargets != undo.resultingTargets { try draft.saveTargets(undo.previousTargets, writer: writer) }
        self = draft
    }
}
