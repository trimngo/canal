import Foundation

extension Capture {
    /// Search stays entirely on-device. Notes are searchable as well as titles.
    public func matchesInboxSearch(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace })
        let content = text + "\n" + (notes ?? "")
        return terms.allSatisfy {
            content.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

extension Ledger {
    public func searchInbox(_ query: String, categoryID: String? = nil) -> [Capture] {
        let ranks = Dictionary(uniqueKeysWithValues: inboxSnapshot.ranked.enumerated().map { ($0.element.id, $0.offset) })
        return captures.filter { idea in
            guard idea.deletedAt == nil, capture(idea, matchesCategory: categoryID) else { return false }
            var searchable = idea
            searchable.notes = (idea.notes ?? "") + "\n" + categoryIDs(for: idea).map { categoryPath($0) }.joined(separator: "\n")
            return searchable.matchesInboxSearch(query)
        }.sorted {
            let aRank = ranks[$0.id], bRank = ranks[$1.id]
            if let aRank, let bRank { return aRank < bRank }
            if (aRank != nil) != (bRank != nil) { return aRank != nil }
            let a = $0.rankingArrivalDate(), b = $1.rankingArrivalDate()
            return a == b ? $0.id < $1.id : a > b
        }
    }
}
