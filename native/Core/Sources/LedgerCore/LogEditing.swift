import Foundation

extension Ledger {
    /// Edit only the captured words. Use the current record so a text correction
    /// cannot restore stale categories, mood, or timestamps from an open sheet.
    public mutating func updateLogActivity(id: String, activity: String, writer: String) throws {
        guard !isLogDeleted(id) else { throw LedgerError.deletedSample }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw LedgerError.invalidSlot }
        let text = activity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else { throw LedgerError.invalidActivity }
        guard entries[index].activity != text else { return }
        entries[index].activity = text
        entries[index].revision = nextRevision(writer: writer)
    }
}
