import Foundation
import NaturalLanguage
import LedgerCore

/// All NaturalLanguage access is serialized and stays off the main actor.
actor AutomaticCategories {
    static let shared = AutomaticCategories()
    private var vectors: [String: [Double]] = [:]
    private var trainingKey: Int?
    private var learned: OfflineCategoryModel?
    private enum Cached { case match(CategorySuggestion), ambiguous }
    private var results: [String: Cached] = [:]
    private func vector(_ text: String) -> [Double]? {
        let text = OfflineGrouping.normalized(text)
        if let cached = vectors[text] { return cached }
        guard let language = NLLanguageRecognizer.dominantLanguage(for: text),
              let embedding = NLEmbedding.sentenceEmbedding(for: language),
              let value = embedding.vector(for: text) else { return nil }
        // Bounded, transient cache. Neither examples nor vectors leave the device.
        if vectors.count > 1500 { vectors.removeAll(keepingCapacity: true) }
        vectors[text] = value; return value
    }
    func classify(_ ledger: Ledger) -> (logs: [String: CategorySuggestion], ideas: [String: CategorySuggestion]) {
        let logs = ledger.activeEntries.filter { ledger.needsCategoryReview($0) && $0.categorySuggestion == nil }
        let ideas = ledger.captures.filter { $0.deletedAt == nil && $0.categoriesReviewed != true && $0.categorySuggestion == nil && ledger.categoryIDs(for: $0).isEmpty }
        guard !logs.isEmpty || !ideas.isEmpty else { return ([:], [:]) }
        // Ranking votes, goal edits and sync receipts do not retrain the model.
        // A cheap signature also lets ambiguous entries reuse an abstention
        // until confirmed examples or category names actually change.
        var hash = Hasher()
        for category in ledger.categories { hash.combine(category.id); hash.combine(category.name); hash.combine(category.parentID) }
        for entry in ledger.activeEntries where entry.categoryAssignment != .automatic {
            hash.combine(entry.id); hash.combine(entry.activity); hash.combine(entry.categoryIDs); hash.combine(entry.categoryID)
        }
        for idea in ledger.captures where idea.deletedAt == nil && idea.categorySuggestion == nil && !(idea.categoryIDs ?? []).isEmpty {
            hash.combine(idea.id); hash.combine(idea.text); hash.combine(idea.categoryIDs)
        }
        let key = hash.finalize()
        if key != trainingKey {
            learned = OfflineCategoryModel(ledger: ledger); trainingKey = key; results.removeAll(keepingCapacity: true)
        }
        guard let model = learned else { return ([:], [:]) }
        var examples: [(CategoryExample, [Double])] = []
        func suggest(_ text: String) -> CategorySuggestion? {
            let key = OfflineGrouping.normalized(text)
            if let cached = results[key] {
                switch cached { case .match(let value): return value; case .ambiguous: return nil }
            }
            let result = compute(text)
            if results.count > 2000 { results.removeAll(keepingCapacity: true) }
            results[key] = result.map(Cached.match) ?? .ambiguous
            return result
        }
        func compute(_ text: String) -> CategorySuggestion? {
            if let result = model.suggest(text) { return result }
            guard let query = vector(text) else { return nil }
            if examples.isEmpty {
                examples = model.examples.suffix(400).compactMap { example in vector(example.text).map { (example, $0) } }
            }
            let queryNorm = sqrt(query.reduce(0) { $0 + $1 * $1 })
            guard queryNorm > 0 else { return nil }
            let matches = examples.compactMap { example, value -> SemanticCategoryMatch? in
                guard value.count == query.count else { return nil }
                let norm = sqrt(value.reduce(0) { $0 + $1 * $1 })
                guard norm > 0 else { return nil }
                let similarity = zip(query, value).reduce(0) { $0 + $1.0 * $1.1 } / (queryNorm * norm)
                return SemanticCategoryMatch(categoryIDs: example.categoryIDs, similarity: similarity)
            }
            return model.suggest(text, semantic: matches)
        }
        var logResults: [String: CategorySuggestion] = [:], ideaResults: [String: CategorySuggestion] = [:]
        for entry in logs { if Task.isCancelled { break }; logResults[entry.id] = suggest(entry.activity) }
        for idea in ideas { if Task.isCancelled { break }; ideaResults[idea.id] = suggest(idea.text) }
        return (logResults, ideaResults)
    }
}
