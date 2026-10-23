import SwiftUI
import UIKit
import LedgerCore

struct LogReviewRequest: Identifiable {
    let id = UUID()
    let entryIDs: [String]
}

/// Freeze the queue on opening. The navigation action and current draft share
/// one owner, so advancing never leaves a toolbar tied to a previous entry.
struct LogReviewView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let entryIDs: [String]
    @State private var index = 0
    @State private var categories: [String] = []
    @State private var mood: Int?
    @State private var goalID: String?
    @State private var activityDraft = ""
    @State private var error: String?
    private var current: CheckIn? {
        guard index < entryIDs.count else { return nil }
        return store.ledger.activeEntries.first { $0.id == entryIDs[index] }
    }
    var body: some View {
        NavigationStack {
            Group {
                if let entry = current {
                    CategorySelectionList(selection: $categories, activity: entry.activity, timestamp: entry.end, mood: $mood,
                        saveActivity: { try store.updateLogActivity(id: entry.id, activity: $0) },
                        activityDraft: $activityDraft, showsKeyboardDone: false)
                        .id(entry.id)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            LogGoalPicker(goalID: $goalID, categoryIDs: $categories).padding(.horizontal)
                        }
                        .safeAreaInset(edge: .bottom) {
                            VStack(alignment: .leading, spacing: 4) {
                                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                                HStack {
                                    Text("\(index + 1) of \(entryIDs.count)").font(.caption).foregroundStyle(.secondary)
                                        .accessibilityIdentifier("log-review.position")
                                    Spacer()
                                    if entry.intervalStart != nil { Text("Confirmed calendar period").font(.caption).foregroundStyle(.secondary) }
                                }
                            }.padding().background(.bar)
                        }
                } else { Color.clear }
            }
            .navigationTitle("Review logs").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("log-review.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save & next", action: saveAndAdvance)
                        .disabled(current == nil || !store.storageAvailable).accessibilityIdentifier("log-review.save-next")
                }
            }
            .task(id: current?.id) { loadCurrent() }
        }
    }
    private func loadCurrent() {
        let active = Set(store.ledger.activeEntries.map(\.id))
        while index < entryIDs.count, !active.contains(entryIDs[index]) { index += 1 }
        guard let entry = current else { dismiss(); return }
        categories = store.ledger.confirmedCategoryIDs(for: entry)
        mood = entry.mood; goalID = entry.goalID; activityDraft = entry.activity; error = nil
    }
    private func saveAndAdvance() {
        guard let entry = current else { return }
        UIApplication.shared.dismissLedgerKeyboard()
        do {
            try store.reviewLog(entry, categoryIDs: categories, mood: mood, goalID: goalID, activity: activityDraft)
            index += 1
            loadCurrent()
        } catch { self.error = error.localizedDescription }
    }
}
