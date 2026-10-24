import Foundation

public enum CategoryMatching: String, Codable, CaseIterable, Identifiable, Sendable {
    case conservative, broader
    public var id: String { rawValue }
    public var name: String { self == .broader ? "Broader suggestions" : "Cautious suggestions" }
}

public struct CategoryMatchRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var phrase: String
    public var categoryID: String
    public init(id: String = UUID().uuidString, phrase: String, categoryID: String) {
        self.id = id; self.phrase = phrase; self.categoryID = categoryID
    }
}

extension Settings {
    public var effectiveUrgencyPhrases: [String] { urgencyPhrases ?? OfflineInboxUrgency.defaultPhrases }
    public var effectiveCategoryMatching: CategoryMatching { categoryMatching ?? .broader }
}

extension OfflineGrouping {
    /// Literal words/phrases, ignoring punctuation, accents and capitalization.
    public static func matchesPhrase(_ phrase: String, in text: String) -> Bool {
        let value = normalized(phrase)
        return !value.isEmpty && (" " + normalized(text) + " ").contains(" " + value + " ")
    }
}
