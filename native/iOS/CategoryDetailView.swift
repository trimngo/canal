import SwiftUI
import LedgerCore

struct CategoryDetailRequest: Identifiable {
    let id: String
    let name: String
    var start: Date? = nil
    var end: Date? = nil
    var directOnly = false
    var allTime = true
}

/// The common browsing destination. Pickers continue selecting category IDs.
struct CategoryDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let request: CategoryDetailRequest
    @State private var showingLogs = false
    @State private var ranking = false
    @State private var snoozing: Capture?
    @State private var categorizing: CaptureCategoryReviewRequest?
    @State private var showOtherLists = false
    var body: some View {
        let ranked = store.inbox.ranked
        let items = store.ledger.searchInbox("", categoryID: request.id, ranked: ranked)
        let rankedIDs = Set(ranked.map(\.id))
        let priorities = items.filter { rankedIDs.contains($0.id) }
        let unranked = items.filter { !rankedIDs.contains($0.id) && !$0.isDone && $0.isReference != true && !$0.isSnoozed(at: Date()) }
        let other = items.filter { $0.isDone || $0.isReference == true || $0.isSnoozed(at: Date()) }
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("\(items.count) inbox items").font(.headline).accessibilityIdentifier("category-detail.count")
                        Spacer()
                        Button("Categorize", systemImage: "tag") {
                            categorizing = CaptureCategoryReviewRequest(captureIDs: items.map(\.id))
                        }.disabled(items.isEmpty || !store.storageAvailable).accessibilityIdentifier("category-detail.categorize")
                    }
                }
                Section("Ranked ideas (\(priorities.count))") {
                    if priorities.isEmpty { Text("No ranked priority yet.").foregroundStyle(.secondary) }
                    ForEach(priorities) { ideaRow($0) }
                }.accessibilityIdentifier("category-detail.ranked")
                if !unranked.isEmpty {
                    Section("Unranked ideas (\(unranked.count))") { ForEach(unranked) { ideaRow($0) } }
                        .accessibilityIdentifier("category-detail.unranked")
                }
                if !other.isEmpty {
                    Section {
                        DisclosureGroup("Reference, snoozed & completed (\(other.count))", isExpanded: $showOtherLists) {
                            ForEach(other) { ideaRow($0) }
                        }.accessibilityIdentifier("category-detail.other-lists")
                    }
                }
                Section {
                    Button("View log entries", systemImage: "list.bullet") { showingLogs = true }
                        .accessibilityIdentifier("category-detail.logs")
                }
                if store.canUndoCaptureDeletion {
                    Section { Button("Undo deletion") { store.undoCaptureDeletion() }.accessibilityIdentifier("inbox.undo-delete") }
                }
            }.scrollDismissesKeyboard(.interactively).ledgerInputDismissal()
                .navigationTitle(store.ledger.categories.first { $0.id == request.id }?.name ?? request.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("category-detail.close")
                } }
                .sheet(isPresented: $showingLogs) {
                    GroupEntriesView(day: request.start ?? Date(), groupID: request.id, initialName: request.name,
                        rangeStart: request.start, rangeEnd: request.end, allTime: request.allTime, directOnly: request.directOnly)
                }
                .sheet(isPresented: $ranking) { RankingView() }
                .sheet(item: $snoozing) { CaptureSnoozeView(capture: $0) }
                .sheet(item: $categorizing) { CaptureCategoryReviewView(captureIDs: $0.captureIDs) }
        }
    }
    private func ideaRow(_ capture: Capture) -> some View {
        InboxCaptureRow(capture: capture, onRank: { ranking = true }, onSnooze: { snoozing = $0 })
            .accessibilityIdentifier("category-detail.idea.\(capture.id)")
    }
}
