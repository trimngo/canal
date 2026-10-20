import SwiftUI
import LedgerCore

struct CaptureCategoryButton: View {
    @EnvironmentObject private var store: LedgerStore
    let capture: Capture
    let identifier: String
    @State private var showing = false
    private var current: Capture { store.ledger.captures.first { $0.id == capture.id } ?? capture }
    private var names: String { store.ledger.categoryIDs(for: current).map { store.ledger.categoryPath($0) }.joined(separator: " + ") }
    var body: some View {
        Button {
            UIApplication.shared.dismissLedgerKeyboard(); showing = true
        } label: {
            Label(names.isEmpty ? "Categorize" : names, systemImage: "tag")
                .font(.subheadline).lineLimit(2).frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.borderless).accessibilityIdentifier(identifier)
            .accessibilityLabel(names.isEmpty ? "Categorize idea" : "Categories: \(names)")
            .sheet(isPresented: $showing) { CaptureCategoryView(capture: current) }
    }
}

private struct CaptureCategoryView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let capture: Capture
    @State private var selection: [String]
    @State private var error: String?
    init(capture: Capture) {
        self.capture = capture; _selection = State(initialValue: capture.categoryIDs ?? [])
    }
    var body: some View {
        NavigationStack {
            CategorySelectionList(selection: $selection, activity: capture.text, timestamp: capture.createdAt,
                                  selectionHelp: "Use the same categories as your journal. Categorizing an idea does not add logged time. A parent and its subcategory cannot both be selected.")
                .navigationTitle("Idea categories").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            do { try store.categorizeCapture(capture, categoryIDs: selection); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.disabled(!store.storageAvailable).accessibilityIdentifier("idea-categories.done")
                    }
                }
                .alert("Couldn’t save categories", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") { error = nil }
                } message: { Text(error ?? "") }
                .onAppear { selection = store.ledger.categoryIDs(for: capture) }
        }
    }
}
