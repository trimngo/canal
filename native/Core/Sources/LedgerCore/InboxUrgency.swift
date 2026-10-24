import Foundation

/// Timing is independent of category, ranking and snooze. ASAP is not a fake date.
public struct CaptureTiming: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case noDate, asap, dueDate }
    public let kind: Kind
    public let dueAt: Date?
    private init(_ kind: Kind, dueAt: Date? = nil) { self.kind = kind; self.dueAt = dueAt }
    public static let noDate = CaptureTiming(.noDate)
    public static let asap = CaptureTiming(.asap)
    public static func due(_ date: Date) -> CaptureTiming { CaptureTiming(.dueDate, dueAt: date) }
}

public struct InboxUrgency: Equatable, Sendable {
    public enum Reason: String, Sendable {
        case communication = "Communication"
        case meeting = "Meeting arrangement"
        case payment = "Payment"
        case explicit = "Urgency in text"
        case asap = "ASAP"
        case dueDate = "Due date"
    }
    public let timing: CaptureTiming
    public let reason: Reason
    public let isSuggested: Bool
}

/// A small, deterministic offline matcher. It never changes the idea's text or category.
public enum OfflineInboxUrgency {
    private struct Rule {
        let phrase: String
        let expression: NSRegularExpression
        let reason: InboxUrgency.Reason
        init(_ phrase: String, _ pattern: String, _ reason: InboxUrgency.Reason) {
            self.phrase = phrase
            expression = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.reason = reason
        }
    }
    private static let action = #"(?:^|[.!?;\n]|\band\b)\s*(?:(?:i\s+)?(?:need\s+to|have\s+to|must|should)\s+|remember\s+to\s+|please\s+)?"#
    private static let rules: [Rule] = {
        var rules: [Rule] = [
        Rule("ASAP", #"\b(?:asap|as\s+soon\s+as\s+possible)\b"#, .explicit),
        Rule("Urgent", #"^\s*(?:urgent|urgently)\b"#, .explicit),
        Rule("Get back to", action + #"get\s+back\s+to\s+\S"#, .communication),
        Rule("Reply", action + #"reply(?:\s+back)?\s+(?:to\s+\S|(?:(?:a|an|the|my|that|this)\s+)?(?:email|message|invitation|request)\b)"#, .communication),
        Rule("Respond to", action + #"respond\s+to\s+\S"#, .communication),
        Rule("Follow up", action + #"follow\s+up\s+(?:with|on)\s+\S"#, .communication),
        Rule("Reach out to", action + #"reach\s+out\s+to\s+\S"#, .communication)
        ]
        for verb in ["Call", "Email", "Text", "Message", "Contact"] {
            rules.append(Rule(verb, action + NSRegularExpression.escapedPattern(for: verb) + #"\s+(?!(?:lenses|lens|for|it|this|that|a|an|the)\b)\S"#, .communication))
        }
        for verb in ["Schedule", "Arrange", "Book", "Reschedule", "Set up"] {
            rules.append(Rule(verb + " meeting", action + NSRegularExpression.escapedPattern(for: verb) + #"\s+(?:(?:a|an|the|my|our)\s+)?(?:meeting|appointment|call|interview)\b"#, .meeting))
        }
        for noun in ["rent", "bill", "invoice", "taxes", "mortgage", "utilities", "insurance"] {
            rules.append(Rule("Pay " + noun, action + #"(?:pay|settle)\s+(?:(?:a|an|the|my|our|overdue)\s+)*"# + noun + #"s?\b"#, .payment))
        }
        return rules
    }()
    public static var defaultPhrases: [String] { rules.map(\.phrase) }
    public static func suggestion(text: String, notes: String? = nil, phrases: [String]? = nil) -> InboxUrgency? {
        let enabled = phrases ?? defaultPhrases
        for content in [text, notes ?? ""] {
            let range = NSRange(content.startIndex..., in: content)
            for phrase in enabled {
                if let rule = rules.first(where: { $0.phrase == phrase }) {
                    if rule.expression.firstMatch(in: content, range: range) != nil {
                        return InboxUrgency(timing: .asap, reason: rule.reason, isSuggested: true)
                    }
                } else if OfflineGrouping.matchesPhrase(phrase, in: content) {
                    return InboxUrgency(timing: .asap, reason: .explicit, isSuggested: true)
                }
            }
        }
        return nil
    }
}

extension Capture {
    public var urgency: InboxUrgency? { urgency(phrases: nil) }
    public func urgency(phrases: [String]?) -> InboxUrgency? {
        guard let timing else { return OfflineInboxUrgency.suggestion(text: text, notes: notes, phrases: phrases) }
        switch timing.kind {
        case .noDate: return nil
        case .asap: return InboxUrgency(timing: timing, reason: .asap, isSuggested: false)
        case .dueDate:
            guard timing.dueAt != nil else { return nil }
            return InboxUrgency(timing: timing, reason: .dueDate, isSuggested: false)
        }
    }
}

extension Ledger {
    /// Show all active dated/ASAP ideas, including ones that have never been ranked.
    /// Dated items come first by deadline; older ASAP items remain easy to find.
    public func urgentCaptures(at now: Date = Date()) -> [Capture] {
        activeCaptures(at: now).filter { urgency(for: $0) != nil }.sorted {
            let a = urgency(for: $0)?.timing.dueAt, b = urgency(for: $1)?.timing.dueAt
            if let a, let b, a != b { return a < b }
            if (a != nil) != (b != nil) { return a != nil }
            return $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
    }
    public func urgency(for capture: Capture) -> InboxUrgency? { capture.urgency(phrases: settings.urgencyPhrases) }
    public mutating func setCaptureTiming(_ id: String, timing: CaptureTiming?, writer: String) throws {
        guard let index = captures.firstIndex(where: { $0.id == id }), captures[index].deletedAt == nil else { throw LedgerError.deletedCapture }
        guard captures[index].timing != timing else { return }
        captures[index].timing = timing
        captures[index].revision = nextRevision(writer: writer)
    }
}
