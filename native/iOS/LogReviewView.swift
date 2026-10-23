import SwiftUI
import UIKit
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
    @State private var goalID: String?
    @State private var error: String?
    @State private var loaded = false
    var body: some View {
        CategorySelectionList(selection: $categories, activity: entry.activity, timestamp: entry.end, mood: $mood,
                              saveActivity: { try store.updateLogActivity(id: entry.id, activity: $0) }, showsKeyboardDone: false)
            .safeAreaInset(edge: .top, spacing: 0) {
                LogGoalPicker(goalID: $goalID, categoryIDs: $categories).padding(.horizontal)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save & next") {
                        UIApplication.shared.dismissLedgerKeyboard()
                        do { try store.reviewLog(entry, categoryIDs: categories, mood: mood, goalID: goalID); didSave() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(!store.storageAvailable).accessibilityIdentifier("log-review.save-next")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    HStack {
                        Text("\(position) of \(count)").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("log-review.position")
                        Spacer()
                        if entry.intervalStart != nil { Text("Confirmed calendar period").font(.caption).foregroundStyle(.secondary) }
                    }
                }.padding().background(.bar)
            }
            .onAppear {
                guard !loaded else { return }
                categories = store.ledger.confirmedCategoryIDs(for: entry); mood = entry.mood; goalID = entry.goalID; loaded = true
            }
    }
}
