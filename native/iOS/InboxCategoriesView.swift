import SwiftUI
import LedgerCore

struct CaptureCategoryReviewRequest: Identifiable {
    let id = UUID()
    let captureIDs: [String]
}

struct InboxCategoriesView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: CategoryDetailRequest?
    @State private var review: CaptureCategoryReviewRequest?
    @State private var showingHelp = false
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.ledger.inboxCategorySummaries(ranked: store.inbox.ranked)) { row in
                    Button {
                        selectedCategory = CategoryDetailRequest(id: row.id, name: row.name)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(row.name).fontWeight(.medium)
                                Spacer()
                                Text("\(row.count)").monospacedDigit().foregroundStyle(.secondary)
                            }
                            if let idea = row.topRanked, let rank = row.overallRank {
                                Text("Top ranked: #\(rank) · \(idea.text)").lineLimit(2)
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                Text("No ranked priority yet").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.leading, CGFloat(row.depth) * 12).padding(.vertical, 3)
                    }.buttonStyle(.plain).accessibilityIdentifier("inbox.categories.\(row.id)")
                }
                if !store.ledger.captures.contains(where: { $0.deletedAt == nil }) {
                    Text("Capture an idea to start.").foregroundStyle(.secondary)
                }
            }.navigationTitle("Inbox categories").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu("Categorize", systemImage: "tag") {
                            reviewButton("Uncategorized ideas", uncategorizedOnly: true)
                            reviewButton("All ideas", uncategorizedOnly: false)
                        }.accessibilityIdentifier("inbox.categories.categorize")
                        Button { showingHelp = true } label: { Image(systemName: "info.circle") }
                            .accessibilityLabel("About inbox categories")
                            .popover(isPresented: $showingHelp) {
                                Text("These are the same categories as your logs. Counts include all saved items, including completed, reference and snoozed ideas. Parents include descendants, counting each idea once. Top ranked uses your overall priorities; items awaiting ranking can change it. Categorizing never adds logged time.")
                                    .font(.subheadline).padding().frame(width: 290).presentationCompactAdaptation(.popover)
                            }
                    }
                }
                .sheet(item: $review) { CaptureCategoryReviewView(captureIDs: $0.captureIDs) }
                .sheet(item: $selectedCategory) { CategoryDetailView(request: $0) }
        }
    }
    private func reviewButton(_ label: String, uncategorizedOnly: Bool) -> some View {
        let ids = store.ledger.inboxCategorizationIDs(uncategorizedOnly: uncategorizedOnly)
        return Button("\(label) (\(ids.count))") { review = CaptureCategoryReviewRequest(captureIDs: ids) }
            .disabled(ids.isEmpty || !store.storageAvailable)
    }
}

/// Save one item at a time without starting or changing a ranking session.
struct CaptureCategoryReviewView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let captureIDs: [String]
    @State private var index = 0
    private var current: Capture? {
        guard index < captureIDs.count else { return nil }
        return store.ledger.captures.first { $0.id == captureIDs[index] && $0.deletedAt == nil }
    }
    var body: some View {
        NavigationStack {
            Group {
                if let capture = current {
                    CaptureCategoryReviewEntry(capture: capture, position: index + 1, count: captureIDs.count) {
                        index += 1; advancePastMissing()
                    }.id(capture.id)
                } else { Color.clear }
            }.navigationTitle("Categorize ideas").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("idea-review.close")
                } }
                .task(id: current?.id) { advancePastMissing() }
        }
    }
    private func advancePastMissing() {
        let existing = Set(store.ledger.captures.filter { $0.deletedAt == nil }.map(\.id))
        while index < captureIDs.count, !existing.contains(captureIDs[index]) { index += 1 }
        if index >= captureIDs.count { dismiss() }
    }
}

private struct CaptureCategoryReviewEntry: View {
    @EnvironmentObject private var store: LedgerStore
    let capture: Capture
    let position: Int
    let count: Int
    let didSave: () -> Void
    @State private var categories: [String] = []
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        CategorySelectionList(selection: $categories, activity: capture.text, timestamp: capture.createdAt,
            saveActivity: { try store.updateCaptureText(capture, text: $0) },
            selectionHelp: "These are the same categories as your logs. Categorization does not change ranking or add logged time.")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    HStack {
                        Text("\(position) of \(count)").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("idea-review.position")
                        Spacer()
                        Button("Save & next") {
                            do { try store.categorizeCapture(capture, categoryIDs: categories); didSave() }
                            catch { self.error = error.localizedDescription }
                        }.buttonStyle(.borderedProminent).disabled(!store.storageAvailable)
                            .accessibilityIdentifier("idea-review.save-next")
                    }
                }.padding().background(.bar)
            }
            .onAppear { if !loaded { categories = store.ledger.categoryIDs(for: capture); loaded = true } }
    }
}
