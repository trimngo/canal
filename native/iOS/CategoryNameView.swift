import SwiftUI
import LedgerCore

struct CategoryNameView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let category: LedgerCategory?
    let parentID: String?
    let didSave: () -> Void
    @State private var name = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Form {
                TextField("Category name", text: $name).focused($focused).accessibilityIdentifier("category-name.field")
                if let parentID { Text("Under \(store.ledger.categoryPath(parentID))").foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(category == nil ? "New category" : "Rename category")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                try store.editCategory(id: category?.id, name: name, parent: parentID)
                                didSave(); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                            .accessibilityIdentifier("category-name.save")
                    }
                }
                .onAppear { name = category?.name ?? ""; focused = true }
        }
    }
}
