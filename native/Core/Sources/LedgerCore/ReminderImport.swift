import Foundation

/// The adapter supplies opaque identities for one reminder. Both its external
/// identity and its device-local identity can be retained as import aliases.
public struct ReminderSnapshot: Equatable, Sendable {
    public let identifiers: [String]
    public let title: String
    public let notes: String?
    public let createdAt: Date?
    public let isCompleted: Bool
    public init(identifiers: [String], title: String, notes: String? = nil,
                createdAt: Date? = nil, isCompleted: Bool = false) {
        self.identifiers = identifiers; self.title = title; self.notes = notes
        self.createdAt = createdAt; self.isCompleted = isCompleted
    }
    public var importText: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? notes : notes.isEmpty || notes == title ? title : title + "\n" + notes
    }
}

/// Separate from the capture revision so learning an external identity later
/// cannot overwrite the idea's completion, deletion, text, or ranking state.
public struct ReminderImportReceipt: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let captureID: String
    public let revision: Revision
}

extension Ledger {
    /// Call only after the ledger has been committed to disk. A receipt alone is
    /// insufficient: the saved copy must still contain this exact source text.
    public func canRemoveImportedReminder(_ snapshot: ReminderSnapshot) -> Bool {
        guard !snapshot.isCompleted, !snapshot.importText.isEmpty else { return false }
        let identities = Set(snapshot.identifiers.filter { !$0.isEmpty })
        let matches = Set((reminderImports ?? []).filter { identities.contains($0.id) }.map(\.captureID))
        guard matches.count == 1, let id = matches.first, let capture = captures.first(where: { $0.id == id }) else { return false }
        return capture.text == snapshot.importText
    }
    /// One-way, additive import. Keep receipts in backups and Watch sync, and
    /// preserve existing ideas even when the source is edited or disappears.
    @discardableResult
    public mutating func importReminders(_ snapshots: [ReminderSnapshot], writer: String,
                                        now: Date = Date()) -> Int {
        var added = 0
        var receipts = Dictionary((reminderImports ?? []).map { ($0.id, $0.captureID) }, uniquingKeysWith: { first, _ in first })
        var captureIDs = Set(captures.map(\.id))
        for snapshot in snapshots where !snapshot.isCompleted {
            let ids = snapshot.identifiers.filter { !$0.isEmpty }.reduce(into: [String]()) { ids, id in
                if !ids.contains(id) { ids.append(id) }
            }
            guard let preferred = ids.first else { continue }
            let text = snapshot.importText
            guard !text.isEmpty else { continue }
            let captureID = ids.compactMap { receipts[$0] }.first ?? "reminder-\(preferred)"
            if !captureIDs.contains(captureID) {
                let timestamp = snapshot.createdAt.flatMap { $0.timeIntervalSince1970.isFinite ? $0 : nil } ?? now
                // External reminder notes may exceed the manual input limit.
                // Keep their full text rather than truncate or block the batch.
                captures.append(Capture(id: captureID, text: text, createdAt: timestamp, revision: nextRevision(writer: writer)))
                captureIDs.insert(captureID); added += 1
            }
            for id in ids where receipts[id] == nil {
                let receipt = ReminderImportReceipt(id: id, captureID: captureID, revision: nextRevision(writer: writer))
                reminderImports = (reminderImports ?? []) + [receipt]
                receipts[id] = captureID
            }
        }
        return added
    }
}
