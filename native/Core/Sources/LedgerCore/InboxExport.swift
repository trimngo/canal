import Foundation

public struct InboxExport: Equatable, Sendable {
    public let count: Int
    public let text: String
}

extension Ledger {
    /// Export the whole inbox, independently of the screen's completed filter.
    /// Preserve full text and original timestamps; deleted ideas stay excluded.
    public var inboxExport: InboxExport {
        let snapshot = inboxSnapshot
        let ranks = Dictionary(uniqueKeysWithValues: snapshot.ranked.enumerated().map { ($0.element.id, $0.offset + 1) })
        let backlog = Set(snapshot.backlog.map(\.id))
        let inProgress = Set(snapshot.inProgress.map(\.id))
        let now = Date()
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
            let list: String, rank: String
            if idea.isDone { list = "Completed"; rank = "Not ranked" }
            else if idea.isReference == true { list = "Reference"; rank = "Not ranked" }
            else if idea.isSnoozed(at: now) { list = "Snoozed"; rank = "Not ranked" }
            else if let position = ranks[idea.id] { list = "Top \(InboxRanking.priorityLimit) Priorities"; rank = String(position) }
            else if backlog.contains(idea.id) { list = "Backlog"; rank = "Evaluated, outside Top \(InboxRanking.priorityLimit)" }
            else if inProgress.contains(idea.id) { list = "In progress"; rank = "Placement incomplete" }
            else { list = "New Ideas"; rank = "Not evaluated" }
            let labels = categoryIDs(for: idea).map { categoryPath($0) }
            let categories = "\n   Categories: " + (labels.isEmpty ? "Uncategorized" : labels.joined(separator: "; ")) + (idea.categorySuggestion == nil ? "" : " (Suggested, awaiting review)")
            let notes = idea.notes.map { "\n   Notes: " + $0.replacingOccurrences(of: "\n", with: "\n   ") } ?? ""
            let snooze = idea.snoozeReturnDate().map { "\n   " + ($0 > now ? "Snoozed until: " : "Returned from snooze: ") + formatter.string(from: $0) } ?? ""
            let urgency = urgency(for: idea)
            let timing = urgency.map { value in
                "\n   Timing: " + (value.timing.dueAt.map { "Due " + formatter.string(from: $0) } ?? "ASAP") +
                    (value.isSuggested ? " (Suggested: \(value.reason.rawValue))" : "")
            } ?? "\n   Timing: No date"
            return "\(index + 1). \(content)\n   Captured: \(formatter.string(from: idea.createdAt))\n   Status: \(status)\n   List: \(list)\n   Rank: \(rank)\(categories)\(notes)\(snooze)\(timing)"
        }
        let noun = ideas.count == 1 ? "idea" : "ideas"
        return InboxExport(count: ideas.count, text: (["Dash inbox — \(ideas.count) \(noun)"] + items).joined(separator: "\n\n"))
    }
}
