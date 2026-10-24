import Foundation

/// Additive wire fields: older ledgers without this record remain unconfirmed.
/// Reasons explain the evidence, rather than presenting a misleading score.
public struct CategorySuggestion: Codable, Equatable, Sendable {
    public var categoryIDs: [String]
    public var reason: String
    public var sourceText: String
    public init(categoryIDs: [String], reason: String, sourceText: String) {
        self.categoryIDs = categoryIDs.sorted(); self.reason = reason
        self.sourceText = OfflineGrouping.normalized(sourceText)
    }
}
public struct CategoryExample: Equatable, Sendable {
    public var text: String
    public var categoryIDs: [String]
    public init(text: String, categoryIDs: [String]) { self.text = text; self.categoryIDs = categoryIDs.sorted() }
}
public struct SemanticCategoryMatch: Sendable {
    public let categoryIDs: [String]
    public let similarity: Double
    public init(categoryIDs: [String], similarity: Double) { self.categoryIDs = categoryIDs; self.similarity = similarity }
}

/// A shared conservative classifier. Only explicit confirmations teach it.
/// Platform sentence embeddings are optional evidence; this core works offline
/// even when a device has no embedding model available for its language.
public struct OfflineCategoryModel: Sendable {
    public let examples: [CategoryExample]
    private let categories: [LedgerCategory]
    private let tokensByGroup: [String: Set<String>]
    private let labels: [String: [String]]
    private static let stop = Set("a an and are as at be been by do doing for from go going have i in is it just me my of on or some that the then this to was were with you your need want still about work working task idea thing today tomorrow yesterday now".split(separator: " ").map(String.init))
    private static func tokens(_ text: String) -> Set<String> {
        Set(OfflineGrouping.normalized(text).split(separator: " ").map(String.init).filter { $0.count >= 3 && !stop.contains($0) })
    }
    public init(ledger: Ledger) {
        categories = ledger.categories
        examples = ledger.activeEntries.compactMap { entry in
            let ids = ledger.confirmedCategoryIDs(for: entry)
            return ids.isEmpty ? nil : CategoryExample(text: entry.activity, categoryIDs: ids)
        } + ledger.captures.filter { $0.deletedAt == nil && $0.categorySuggestion == nil }.compactMap { capture in
            let ids = ledger.categoryIDs(for: capture)
            return ids.isEmpty ? nil : CategoryExample(text: capture.text, categoryIDs: ids)
        }
        var words: [String: Set<String>] = [:], values: [String: [String]] = [:]
        for example in examples {
            let key = example.categoryIDs.joined(separator: "|")
            words[key, default: []].formUnion(Self.tokens(example.text)); values[key] = example.categoryIDs
        }
        tokensByGroup = words; labels = values
    }
    public func suggest(_ text: String, semantic: [SemanticCategoryMatch] = []) -> CategorySuggestion? {
        let normalized = OfflineGrouping.normalized(text), query = Self.tokens(text)
        guard !query.isEmpty else { return nil }
        func result(_ ids: [String], _ reason: String) -> CategorySuggestion {
            CategorySuggestion(categoryIDs: ids, reason: reason, sourceText: text)
        }
        let exact = Set(examples.filter { OfflineGrouping.normalized($0.text) == normalized }.map { $0.categoryIDs.joined(separator: "|") })
        if exact.count == 1, let key = exact.first { return result(key.components(separatedBy: "|"), "Same as a confirmed entry") }
        if exact.count > 1 { return nil }
        // A uniquely named category is useful for custom names and acronyms.
        let names = categories.filter {
            let name = OfflineGrouping.normalized($0.name)
            return name.count >= 3 && (" " + normalized + " ").contains(" " + name + " ")
        }.sorted { $0.name.count > $1.name.count }
        if let name = names.first {
            guard names.dropFirst().allSatisfy({ OfflineGrouping.normalized(name.name).contains(OfflineGrouping.normalized($0.name)) }) else { return nil }
            return result([name.id], "Matched \(name.name)")
        }
        // Distinctive vocabulary learned across categories; generic shared
        // words cannot decide an ambiguous assignment.
        var scores: [(String, Int, Set<String>)] = []
        for (key, words) in tokensByGroup {
            let unique = query.intersection(words).filter { word in
                tokensByGroup.allSatisfy { $0.key == key || !$0.value.contains(word) }
            }
            if !unique.isEmpty { scores.append((key, unique.count, Set(unique))) }
        }
        scores.sort { $0.1 > $1.1 }
        if let best = scores.first, best.1 >= 2, scores.count == 1 || best.1 >= scores[1].1 + 2,
           let ids = labels[best.0] {
            return result(ids, "Matched confirmed vocabulary: " + best.2.sorted().prefix(2).joined(separator: ", "))
        }
        var grouped: [String: Double] = [:]
        for match in semantic where !match.categoryIDs.isEmpty {
            grouped[match.categoryIDs.sorted().joined(separator: "|"), default: -1] = max(grouped[match.categoryIDs.sorted().joined(separator: "|"), default: -1], match.similarity)
        }
        let ranked = grouped.sorted { $0.value > $1.value }
        if let best = ranked.first, best.value >= 0.84, ranked.count == 1 || best.value - ranked[1].value >= 0.12 {
            return result(best.key.components(separatedBy: "|"), "Similar to confirmed entries")
        }
        // Seed vocabulary is a fallback, never a replacement for an ambiguous
        // learned or custom-category choice.
        if scores.isEmpty && names.isEmpty, let id = OfflineGrouping.category(for: text, groups: categories) {
            return result([id], "Matched activity vocabulary")
        }
        return nil
    }
}

extension Ledger {
    public func effectiveCategoryIDs(for entry: CheckIn) -> [String] {
        if entry.categoryAssignment != .automatic { return confirmedCategoryIDs(for: entry) }
        guard let suggestion = entry.categorySuggestion,
              suggestion.sourceText == OfflineGrouping.normalized(entry.activity) else { return [] }
        let known = Set(categories.map(\.id)), raw = suggestion.categoryIDs.filter(known.contains)
        return raw.filter { id in !raw.contains { other in other != id && descendants(of: id).contains { $0.id == other } } }
    }
    public func needsCategoryReview(_ entry: CheckIn) -> Bool {
        entry.categoryAssignment == .automatic || (entry.categoryAssignment == nil && confirmedCategoryIDs(for: entry).isEmpty)
    }
    public mutating func suggestCategories(_ suggestion: CategorySuggestion, logID: String, writer: String) throws {
        guard let i = entries.firstIndex(where: { $0.id == logID }), !isLogDeleted(logID), needsCategoryReview(entries[i]),
              entries[i].categorySuggestion == nil, suggestion.sourceText == OfflineGrouping.normalized(entries[i].activity) else { return }
        try validateCategories(suggestion.categoryIDs)
        entries[i].categorySuggestion = suggestion; entries[i].categoryAssignment = .automatic
        entries[i].categoryIDs = suggestion.categoryIDs; entries[i].categoryID = suggestion.categoryIDs.first
        entries[i].revision = nextRevision(writer: writer)
    }
    public mutating func suggestCategories(_ suggestion: CategorySuggestion, captureID: String, writer: String) throws {
        guard let i = captures.firstIndex(where: { $0.id == captureID }), captures[i].deletedAt == nil,
              captures[i].categoriesReviewed != true, captures[i].categorySuggestion == nil, categoryIDs(for: captures[i]).isEmpty,
              suggestion.sourceText == OfflineGrouping.normalized(captures[i].text) else { return }
        try validateCategories(suggestion.categoryIDs)
        captures[i].categorySuggestion = suggestion; captures[i].categoryIDs = suggestion.categoryIDs
        captures[i].revision = nextRevision(writer: writer)
    }
}
