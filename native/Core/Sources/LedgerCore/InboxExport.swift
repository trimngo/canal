import Foundation

public struct InboxExport: Equatable, Sendable {
    public let count: Int
    public let text: String
}

extension Ledger {
    /// Export the whole inbox, independently of the screen's completed filter.
    /// Preserve full text and original timestamps; deleted ideas stay excluded.
    public var inboxExport: InboxExport {
        let ranks = Dictionary(uniqueKeysWithValues: rankedCaptureIDs.enumerated().map { ($0.element, $0.offset + 1) })
        let ideas = captures.filter { $0.deletedAt == nil }.sorted {
            if $0.isDone != $1.isDone { return !$0.isDone }
            let a = ranks[$0.id], b = ranks[$1.id]
            if let a, let b { return a < b }
            if (a != nil) != (b != nil) { return a != nil }
            return $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }
        let formatter = ISO8601DateFormatter()
        let items = ideas.enumerated().map { index, idea in
            let content = idea.text.replacingOccurrences(of: "\n", with: "\n   ")
            let status = idea.isDone ? "Completed" : "Open"
            let rank = ranks[idea.id].map { String($0) } ?? "Not ranked"
            let notes = idea.notes.map { "\n   Notes: " + $0.replacingOccurrences(of: "\n", with: "\n   ") } ?? ""
            let snooze = idea.snoozedUntil.map { "\n   Snoozed until: " + formatter.string(from: $0) } ?? ""
            return "\(index + 1). \(content)\n   Captured: \(formatter.string(from: idea.createdAt))\n   Status: \(status)\n   Rank: \(rank)\(notes)\(snooze)"
        }
        let noun = ideas.count == 1 ? "idea" : "ideas"
        return InboxExport(count: ideas.count, text: (["Dash inbox — \(ideas.count) \(noun)"] + items).joined(separator: "\n\n"))
    }
}
