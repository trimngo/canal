import Foundation

extension Ledger {
    /// Replace only the source branch's labels, retaining all unrelated shares
    /// (including tombstoned category references). The batch is all-or-nothing.
    public mutating func moveLogs(_ ids: Set<String>, from source: String, to destination: String, writer: String) throws {
        guard categories.contains(where: { $0.id == destination }),
              source == "uncategorized" || categories.contains(where: { $0.id == source }) else { throw LedgerError.invalidCategory }
        let branch = Set([source] + descendants(of: source).map(\.id))
        let known = Set(categories.map(\.id))
        var draft = self
        for id in ids.sorted() {
            guard !isLogDeleted(id), let index = draft.entries.firstIndex(where: { $0.id == id }) else { throw LedgerError.deletedSample }
            let original = draft.entries[index]
            let raw = original.categoryAssignment == .automatic ? [] : (original.categoryIDs ?? original.categoryID.map { [$0] } ?? [])
            let matches = source == "uncategorized" ? (raw.isEmpty || raw.contains { !known.contains($0) }) : raw.contains { branch.contains($0) }
            guard matches else { throw LedgerError.invalidCategory }
            var labels = raw.filter { source == "uncategorized" ? known.contains($0) : !branch.contains($0) }
            labels.append(destination); labels = Array(Set(labels)).sorted()
            try draft.validateCategories(labels.filter { known.contains($0) })
            draft.entries[index].categoryIDs = labels
            draft.entries[index].categoryID = labels.first { known.contains($0) }
            draft.entries[index].categoryAssignment = .manual
            if original.goalID != nil { draft.entries[index].goalShare = draft.datedGoalShare(for: draft.entries[index], goalID: original.goalID) }
            draft.entries[index].revision = draft.nextRevision(writer: writer)
        }
        draft.prepareGroupSuggestions(writer: writer)
        self = draft
    }
}
