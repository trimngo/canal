import Foundation

extension Ledger {
    public func categoryIDs(for capture: Capture) -> [String] {
        let existing = Set(categories.map(\.id))
        return (capture.categoryIDs ?? []).filter(existing.contains)
    }

    public mutating func categorizeCapture(id: String, categoryIDs: [String], writer: String) throws {
        guard let index = captures.firstIndex(where: { $0.id == id }), captures[index].deletedAt == nil else { throw LedgerError.deletedCapture }
        let ids = Array(Set(categoryIDs)).sorted()
        try validateCategories(ids)
        guard self.categoryIDs(for: captures[index]) != ids else { return }
        captures[index].categoryIDs = ids
        captures[index].revision = nextRevision(writer: writer)
    }

    /// A parent filter includes its descendants. Deleted category references
    /// remain in the raw capture but no longer act as visible labels.
    public func capture(_ capture: Capture, matchesCategory id: String?) -> Bool {
        guard let id else { return true }
        let assigned = categoryIDs(for: capture)
        if id == "uncategorized" { return assigned.isEmpty }
        let family = Set([id] + descendants(of: id).map(\.id))
        return assigned.contains(where: family.contains)
    }
}
