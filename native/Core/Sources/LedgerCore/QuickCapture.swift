import Foundation

/// A Siri note can supply a title, a body, or both. Keep all of the spoken
/// content; supplying only a title must not require another spoken turn.
public enum QuickCapture {
    public static func text(title: String?, body: String?) throws -> String {
        let title = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String
        if title.isEmpty { value = body }
        else if body.isEmpty || title.caseInsensitiveCompare(body) == .orderedSame { value = title }
        else { value = title + "\n" + body }
        guard !value.isEmpty, value.count <= 500 else { throw LedgerError.invalidActivity }
        return value
    }
}

extension Ledger {
    /// Retrying a delivered notification cannot duplicate or move the sample.
    /// This records the response moment, never the scheduled notification time.
    public mutating func saveQuickSample(id: String, at timestamp: Date, activity: String,
                                         writer: String, now: Date = Date()) throws {
        guard !entries.contains(where: { $0.id == id }) else { return }
        try saveSample(id: id, at: timestamp, activity: activity, categoryID: nil, writer: writer, now: now)
    }
}
