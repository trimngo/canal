import SwiftUI
import LedgerCore

struct LogReviewRequest: Identifiable {
    let id = UUID()
    let entryIDs: [String]
}

/// Freeze the queue on opening. Incoming logs never interrupt the current item;
/// each completed save uses the normal ledger transaction and sync path.
struct LogReviewView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let entryIDs: [String]
    @State private var index = 0
    private var current: CheckIn? {
        guard index < entryIDs.count else { return nil }
        return store.ledger.activeEntries.first { $0.id == entryIDs[index] }
    }
    var body: some View {
        NavigationStack {
            Group {
                if let entry = current {
                    LogReviewEntryView(entry: entry, position: index + 1, count: entryIDs.count) { advance() }.id(entry.id)
                } else {
                    Color.clear
                }
            }.navigationTitle("Review logs").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("log-review.close") } }
                .task(id: current?.id) { advancePastMissing() }
        }
    }
    private func advance() { index += 1; advancePastMissing() }
    private func advancePastMissing() {
        let active = Set(store.ledger.activeEntries.map(\.id))
        while index < entryIDs.count, !active.contains(entryIDs[index]) { index += 1 }
        if index >= entryIDs.count { dismiss() }
    }
}

private struct LogReviewEntryView: View {
    @EnvironmentObject private var store: LedgerStore
    let entry: CheckIn
    let position: Int
    let count: Int
    let didSave: () -> Void
    @State private var categories: [String] = []
    @State private var mood: Int?
    @State private var error: String?
    var body: some View {
        CategorySelectionList(selection: $categories, activity: entry.activity, timestamp: entry.end, mood: $mood)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    HStack {
                        Text("\(position) of \(count)").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("log-review.position")
                        Spacer()
                        Button("Save & next") {
                            do { try store.categorize(entry, categoryIDs: categories, mood: mood); didSave() }
                            catch { self.error = error.localizedDescription }
                        }.buttonStyle(.borderedProminent).disabled(!store.storageAvailable)
                            .accessibilityIdentifier("log-review.save-next")
                    }
                }.padding().background(.bar)
            }
            .onAppear { categories = store.ledger.confirmedCategoryIDs(for: entry); mood = entry.mood }
    }
}
