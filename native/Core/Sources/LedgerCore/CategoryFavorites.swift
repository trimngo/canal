import Foundation

extension Ledger {
    /// Parent selection is a bulk action on the current leaf categories.
    public func favoriteSelectionIDs(_ ids: Set<String>) -> Set<String> {
        let index = AllocationCategoryIndex(ledger: self)
        var result = Set<String>()
        func append(_ id: String) {
            let children = index.children(of: id)
            if children.isEmpty, index.leafIDs.contains(id) { result.insert(id) }
            for child in children { append(child.id) }
        }
        for id in ids { append(id) }
        return result
    }
    public var favoriteCategoryIDs: Set<String> { Set(categories.filter { $0.isFavorite == true }.map(\.id)) }
    public mutating func setCategoryFavorites(_ ids: Set<String>, favorite: Bool, writer: String) throws {
        guard ids.isSubset(of: Set(categories.map(\.id))) else { throw LedgerError.invalidCategory }
        let targets = favoriteSelectionIDs(ids)
        let changing = categories.indices.filter { targets.contains(categories[$0].id) && (categories[$0].isFavorite ?? false) != favorite }
        guard !changing.isEmpty else { return }
        let revision = nextRevision(writer: writer)
        for i in changing { categories[i].isFavorite = favorite; categories[i].revision = revision }
    }
}
