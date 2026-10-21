import Foundation

extension Ledger {
    /// Match names anywhere along a category's path, retaining ancestor rows
    /// as context. Searching a parent also shows its descendants in tree order.
    public func searchCategories(_ query: String) -> [LedgerCategory] {
        let ordered = orderedCategories
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return ordered }
        let parents = categoryParents
        var included = Set<String>()
        for category in ordered {
            let path = categoryPath(category.id)
            guard terms.allSatisfy({ path.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) else { continue }
            var id = category.id
            included.insert(id)
            while let parent = parents[id] { included.insert(parent); id = parent }
        }
        return ordered.filter { included.contains($0.id) }
    }
}
