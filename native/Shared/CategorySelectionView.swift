import SwiftUI
import LedgerCore

/// Shared phone/Watch selector. A conflicting selection is replaced only after
/// the user explicitly confirms; the core validates the same rule on save.
struct CategorySelectionPicker: View {
    @EnvironmentObject var store: LedgerStore
    @Binding var selection: [String]
    @State private var showing = false
    @State private var replacing: String?
    private var title: String {
        selection.isEmpty ? "Uncategorized" : selection.map { store.ledger.categoryPath($0) }.joined(separator: " + ")
    }
    var body: some View {
        Button { showing = true } label: {
            HStack { Text("Categories"); Spacer(); Text(title).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
        }.sheet(isPresented: $showing) {
            NavigationStack {
                List {
                    Button("Uncategorized") { selection = [] }
                    ForEach(store.ledger.orderedCategories) { category in
                        Button {
                            if selection.contains(category.id) { selection.removeAll { $0 == category.id } }
                            else if store.ledger.categoryConflicts(category.id, with: selection).isEmpty { selection.append(category.id) }
                            else { replacing = category.id }
                        } label: {
                            HStack {
                                Text(store.ledger.categoryPath(category.id))
                                Spacer()
                                if selection.contains(category.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }.accessibilityIdentifier("category-select.\(category.id)")
                    }
                    Text("Select one or more. Estimated time is divided equally. A parent and its subcategory cannot both be selected.").font(.footnote).foregroundStyle(.secondary)
                }
                .navigationTitle("Categories")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showing = false } } }
                .alert("Replace conflicting categories?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } })) {
                    Button("Replace") {
                        if let id = replacing {
                            let conflicts = Set(store.ledger.categoryConflicts(id, with: selection))
                            selection.removeAll { conflicts.contains($0) }; selection.append(id)
                        }
                        replacing = nil
                    }
                    Button("Cancel", role: .cancel) { replacing = nil }
                } message: {
                    if let id = replacing {
                        Text("Selecting \(store.ledger.categoryPath(id)) replaces \(store.ledger.categoryConflicts(id, with: selection).map { store.categoryName($0) }.joined(separator: ", ")). Other selections are kept.")
                    }
                }
            }
        }
    }
}
