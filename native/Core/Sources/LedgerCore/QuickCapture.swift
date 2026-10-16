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

    /// Siri owns the note grammar. A leading routing word distinguishes an
    /// activity sample from an inbox idea after Siri has delivered the text.
    public static func note(title: String?, body: String?, id: String = UUID().uuidString,
                            at timestamp: Date = Date()) throws -> QuickCaptureEntry {
        let original = try text(title: title, body: body)
        let prefix = original.prefix { !$0.isWhitespace && !":,;–—-".contains($0) }
        let keyword = prefix.lowercased()
        let routed = keyword == "idea" || keyword == "doing"
        let content = routed
            ? String(original.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,;–—-")))
            : original
        guard !content.isEmpty else { throw LedgerError.invalidActivity }
        return QuickCaptureEntry(id: id, destination: keyword == "doing" ? .activity : .idea,
                                 text: content, recordedAt: timestamp)
    }
}

public struct QuickCaptureEntry: Codable, Identifiable, Equatable, Sendable {
    public enum Destination: String, Codable, Sendable { case idea, activity }
    public let id: String
    public let destination: Destination
    public let text: String
    public let recordedAt: Date

    public init(id: String, destination: Destination, text: String, recordedAt: Date) {
        self.id = id; self.destination = destination; self.text = text; self.recordedAt = recordedAt
    }

    /// Pending Watch thoughts from older builds must remain ideas, even if
    /// their text happens to start with "doing".
    public static func decodeQueued(_ data: Data) throws -> QuickCaptureEntry {
        let decoder = JSONDecoder()
        if let entry = try? decoder.decode(Self.self, from: data) { return entry }
        let old = try decoder.decode(Capture.self, from: data)
        return Self(id: old.id, destination: .idea, text: old.text, recordedAt: old.createdAt)
    }
}

extension Ledger {
    public mutating func saveQuickCapture(_ entry: QuickCaptureEntry, writer: String, now: Date = Date()) throws {
        switch entry.destination {
        case .idea: try addCapture(text: entry.text, id: entry.id, writer: writer, now: entry.recordedAt)
        case .activity: try saveQuickSample(id: entry.id, at: entry.recordedAt, activity: entry.text, writer: writer, now: now)
        }
    }

    /// Retrying a delivered notification cannot duplicate or move the sample.
    /// This records the response moment, never the scheduled notification time.
    public mutating func saveQuickSample(id: String, at timestamp: Date, activity: String,
                                         writer: String, now: Date = Date()) throws {
        guard !entries.contains(where: { $0.id == id }) else { return }
        try saveSample(id: id, at: timestamp, activity: activity, categoryID: nil, writer: writer, now: now)
    }
}
