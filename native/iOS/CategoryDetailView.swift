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
    @State private var snoozing: Capture?
    @State private var categorizing: CaptureCategoryReviewRequest?
    @State private var showOtherLists = false
    @State private var progress: [DatedGoalProgress] = []
    @State private var calculationID = UUID()
    var body: some View {
        let ranked = store.inbox.ranked
        let items = store.ledger.searchInbox("", categoryID: request.id, ranked: ranked)
        let rankedIDs = Set(ranked.map(\.id))
        let focus = items.filter { store.ledger.isFocusTask($0) }
        let focusIDs = Set(focus.map(\.id))
        let priorities = items.filter { rankedIDs.contains($0.id) && !focusIDs.contains($0.id) }
        let unranked = items.filter { !focusIDs.contains($0.id) && !rankedIDs.contains($0.id) && !$0.isDone && $0.isReference != true && !$0.isSnoozed(at: Date()) }
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
                if !focus.isEmpty {
                    Section("Focus (\(focus.count))") {
                        ForEach(focus.sorted { $0.timing!.dueAt! < $1.timing!.dueAt! }) { task in
                            VStack(alignment: .leading, spacing: 6) {
                                ideaRow(task)
                                if let row = progress.first(where: { $0.id == task.id }) { FocusTaskProgressView(row: row, showsDeadline: true) }
                            }.accessibilityIdentifier("category-detail.focus.\(task.id)")
                        }
                    }
                }
                Section("Ranked ideas (\(priorities.count))") {
                    if priorities.isEmpty { Text("No ranked priority yet.").foregroundStyle(.secondary) }
                    ForEach(priorities) { ideaRow($0) }
                }
                if !unranked.isEmpty {
                    Section("Unranked ideas (\(unranked.count))") { ForEach(unranked) { ideaRow($0) } }
                }
                if !other.isEmpty {
                    Section {
                        Button {
                            showOtherLists.toggle()
                        } label: {
                            HStack {
                                Text("Reference, snoozed & completed (\(other.count))")
                                Spacer()
                                Image(systemName: showOtherLists ? "chevron.down" : "chevron.right").font(.caption)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityValue(showOtherLists ? "Expanded" : "Collapsed")
                            .accessibilityIdentifier("category-detail.other-lists")
                        if showOtherLists { ForEach(other) { ideaRow($0) } }
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
                .onChange(of: store.ledger) { _, _ in calculationID = UUID() }
                .task(id: calculationID) {
                    let ledger = store.ledger
                    let result = await Task.detached(priority: .userInitiated) { ledger.focusTaskProgress() }.value
                    if !Task.isCancelled { progress = result }
                }
                .sheet(isPresented: $showingLogs) {
                    GroupEntriesView(day: request.start ?? Date(), groupID: request.id, initialName: request.name,
                        rangeStart: request.start, rangeEnd: request.end, allTime: request.allTime, directOnly: request.directOnly)
                }
                .sheet(item: $snoozing) { CaptureSnoozeView(capture: $0) }
                .sheet(item: $categorizing) { CaptureCategoryReviewView(captureIDs: $0.captureIDs) }
        }
    }
    private func ideaRow(_ capture: Capture) -> some View {
        InboxCaptureRow(capture: capture, onSnooze: { snoozing = $0 })
    }
}
