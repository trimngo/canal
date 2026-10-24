import SwiftUI
import UIKit
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

/// Independent of ranking. All drafts and the keyboard-visible save action
/// belong to the queue, so an inline edit cannot save against the next item.
struct CaptureCategoryReviewView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let captureIDs: [String]
    @State private var index = 0
    @State private var categories: [String] = []
    @State private var text = ""
    @State private var error: String?
    @State private var snoozing: Capture?
    private var current: Capture? {
        guard index < captureIDs.count else { return nil }
        return store.ledger.captures.first { $0.id == captureIDs[index] && $0.deletedAt == nil }
    }
    var body: some View {
        NavigationStack {
            Group {
                if let capture = current {
                    CategorySelectionList(selection: $categories, activity: capture.text, timestamp: capture.createdAt,
                        activityMaxLength: nil, saveActivity: { try store.updateCaptureText(capture, text: $0) },
                        activityDraft: Binding(get: { text }, set: { if current?.id == capture.id { text = $0 } }),
                        showsKeyboardDone: false,
                        selectionHelp: "These are the same categories as your logs. Categorization does not change ranking or add logged time.")
                        .id(capture.id)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                if let suggestion = capture.categorySuggestion { Text("Suggested · \(suggestion.reason)").font(.caption).foregroundStyle(.secondary) }
                                CaptureReviewActions(capture: capture, identifier: "idea-review", onHandled: advance, onSnooze: { snoozing = $0 })
                                InlineCaptureNotes(capture: capture, identifier: "idea-review.notes")
                            }.padding(.horizontal).background(.bar)
                        }
                } else { Color.clear }
            }.navigationTitle("Categorize ideas").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        HStack {
                            Text("\(index + 1) of \(captureIDs.count)").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("idea-review.position")
                            Spacer()
                            if store.canUndoCaptureDeletion { Button("Undo delete") { store.undoCaptureDeletion() }.accessibilityIdentifier("idea-review.undo-delete") }
                        }
                    }.padding().background(.bar)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("idea-review.close") }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save & next") {
                            UIApplication.shared.dismissLedgerKeyboard()
                            guard let capture = current else { return }
                            do { try store.reviewCapture(capture, text: text, categoryIDs: categories); advance() }
                            catch { self.error = error.localizedDescription }
                        }.disabled(current == nil || !store.storageAvailable).accessibilityIdentifier("idea-review.save-next")
                    }
                }
                .sheet(item: $snoozing) { CaptureSnoozeView(capture: $0) }
                .task(id: current?.id) { load() }
        }
    }
    private func advance() { index += 1; load() }
    private func load() {
        let existing = Set(store.ledger.captures.filter { $0.deletedAt == nil }.map(\.id))
        while index < captureIDs.count, !existing.contains(captureIDs[index]) { index += 1 }
        guard let capture = current else { dismiss(); return }
        categories = store.ledger.categoryIDs(for: capture); text = capture.text; error = nil
    }
}
