import SwiftUI
import LedgerCore

struct CaptureCategoryButton: View {
    @EnvironmentObject private var store: LedgerStore
    let capture: Capture
    let identifier: String
    var compact = false
    var showsAllCategories = false
    @State private var showing = false
    @State private var selection: [String] = []
    private var current: Capture { store.ledger.captures.first { $0.id == capture.id } ?? capture }
    private var names: String { store.ledger.categoryIDs(for: current).map { store.ledger.categoryPath($0) }.joined(separator: " + ") }
    var body: some View {
        Button {
            UIApplication.shared.dismissLedgerKeyboard()
            selection = store.ledger.categoryIDs(for: current); showing = true
        } label: {
            Label((current.categorySuggestion == nil ? "" : "Suggested · ") + (names.isEmpty ? "Categorize" : names), systemImage: "tag")
                .font(compact ? .caption : .subheadline).lineLimit(showsAllCategories ? nil : compact ? 1 : 2).frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.borderless).accessibilityIdentifier(identifier)
            .accessibilityLabel(names.isEmpty ? "Categorize idea" : "Categories: \(names)")
            .sheet(isPresented: $showing) {
                CaptureCategoryView(capture: current, selection: $selection)
            }
    }
}

private struct CaptureCategoryView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let capture: Capture
    @Binding var selection: [String]
    @State private var error: String?
    private var current: Capture { store.ledger.captures.first { $0.id == capture.id } ?? capture }
    var body: some View {
        NavigationStack {
            CategorySelectionList(selection: $selection, activity: current.text, timestamp: capture.createdAt,
                                  activityMaxLength: nil, saveActivity: { try store.updateCaptureText(capture, text: $0) },
                                  selectionHelp: "Use the same categories as your journal. Categorizing an idea does not add logged time. A parent and its subcategory cannot both be selected.")
                .safeAreaInset(edge: .top) {
                    if let suggestion = current.categorySuggestion { Text("Suggested · \(suggestion.reason)").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 4).background(.bar) }
                }
                .navigationTitle("Idea categories").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red).padding().background(.regularMaterial)
                            .accessibilityIdentifier("idea-categories.error")
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            do { try store.categorizeCapture(capture, categoryIDs: selection); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.disabled(!store.storageAvailable).accessibilityIdentifier("idea-categories.done")
                    }
                }
        }
    }
}
