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
    public func searchInbox(_ query: String) -> [Capture] {
        captures.filter { $0.deletedAt == nil && $0.matchesInboxSearch(query) }.sorted {
            let a = $0.rankingArrivalDate(), b = $1.rankingArrivalDate()
            return a == b ? $0.id < $1.id : a > b
        }
    }
}
