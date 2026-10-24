import SwiftUI
import UIKit
import LedgerCore

struct LogReviewRequest: Identifiable {
    let id = UUID()
    let entryIDs: [String]
    var calendarIDs: [String] = []
}
private enum LogReviewItem: Hashable {
    case sample(String), calendar(String)
    var id: String { switch self { case .sample(let id): return "log:" + id; case .calendar(let id): return "event:" + id } }
}

/// The queue and drafts have one owner, including the navigation save action.
struct LogReviewView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let entryIDs: [String]
    var calendarIDs: [String] = []
    @State private var queue: [LogReviewItem] = []
    @State private var loaded = false
    @State private var index = 0
    @State private var categories: [String] = []
    @State private var mood: Int?
    @State private var goalID: String?
    @State private var activityDraft = ""
    @State private var error: String?
    private var item: LogReviewItem? { index < queue.count ? queue[index] : nil }
    private var event: CalendarEventRecord? {
        guard case .calendar(let id) = item else { return nil }
        return store.ledger.calendarEvents?.first { $0.id == id && $0.decision == .pending }
    }
    private var current: CheckIn? {
        switch item {
        case .sample(let id): return store.ledger.activeEntries.first { $0.id == id }
        case .calendar:
            guard let event else { return nil }
            var sample = CheckIn(end: event.snapshot.end, activity: event.snapshot.title, categoryID: nil,
                revision: event.revision, sampleID: event.logID, categoryAssignment: .automatic)
            sample.intervalStart = event.snapshot.start
            return sample
        case nil: return nil
        }
    }
    var body: some View {
        NavigationStack {
            Group {
                if let entry = current {
                    CategorySelectionList(selection: $categories, activity: entry.activity, timestamp: entry.end, mood: $mood,
                        saveActivity: { if event == nil { try store.updateLogActivity(id: entry.id, activity: $0) } },
                        activityDraft: Binding(get: { activityDraft }, set: { if current?.id == entry.id { activityDraft = $0 } }), showsKeyboardDone: false)
                        .id(item?.id)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            VStack(alignment: .leading, spacing: 6) {
                                if let event {
                                    let end = store.ledger.calendarEventEnd(event.snapshot)
                                    Text("Did this happen? · \(event.snapshot.calendarName)").font(.subheadline.bold())
                                    Text("\(event.snapshot.start.formatted(date: .abbreviated, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened)) · \(store.duration(max(0, end.timeIntervalSince(event.snapshot.start) / 60)))")
                                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("log-review.calendar-period")
                                    if end < event.snapshot.end { Text("Ends at your first overlapping log. That log takes over from there.").font(.caption).foregroundStyle(.secondary) }
                                } else if let suggestion = entry.categorySuggestion {
                                    Label("Suggested · \(suggestion.reason)", systemImage: "sparkle").font(.caption).foregroundStyle(.secondary)
                                }
                                LogGoalPicker(goalID: $goalID, categoryIDs: $categories)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 6).background(.bar)
                        }
                        .safeAreaInset(edge: .bottom) {
                            HStack {
                                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                                Text("\(index + 1) of \(queue.count)").font(.caption).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("log-review.position")
                                Spacer()
                                if event != nil { Button("Skip event") { saveAndAdvance(skip: true) }.accessibilityIdentifier("log-review.skip-event") }
                            }.padding().background(.bar)
                        }
                } else { Color.clear }
            }
            .navigationTitle("Review logs").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("log-review.close") }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(event == nil ? "Save & next" : "Confirm & next") { saveAndAdvance() }
                        .disabled(current == nil || !store.storageAvailable).accessibilityIdentifier("log-review.save-next")
                }
            }
            .onAppear {
                if !loaded {
                    queue = entryIDs.map(LogReviewItem.sample) + calendarIDs.map(LogReviewItem.calendar)
                    let ledger = store.ledger
                    func date(_ item: LogReviewItem) -> Date {
                        switch item {
                        case .sample(let id): return ledger.activeEntries.first { $0.id == id }?.end ?? .distantPast
                        case .calendar(let id): return ledger.calendarEvents?.first { $0.id == id }?.snapshot.end ?? .distantPast
                        }
                    }
                    queue.sort { date($0) == date($1) ? $0.id < $1.id : date($0) > date($1) }
                    loaded = true; loadCurrent()
                }
            }
            .onChange(of: current?.id) { _, _ in loadCurrent() }
        }
    }
    private func loadCurrent() {
        while index < queue.count, current == nil { index += 1 }
        guard let entry = current else { if loaded { dismiss() }; return }
        categories = store.ledger.effectiveCategoryIDs(for: entry)
        if event != nil, let suggested = store.ledger.suggestedCategory(for: entry.activity) { categories = [suggested] }
        mood = entry.mood; goalID = entry.goalID; activityDraft = entry.activity; error = nil
    }
    private func saveAndAdvance(skip: Bool = false) {
        guard let entry = current else { return }
        UIApplication.shared.dismissLedgerKeyboard()
        do {
            if let event {
                try store.reviewCalendarEvent(event.id, confirm: !skip, categoryIDs: categories, mood: mood, goalID: goalID, activity: activityDraft)
            } else { try store.reviewLog(entry, categoryIDs: categories, mood: mood, goalID: goalID, activity: activityDraft) }
            index += 1; loadCurrent()
        } catch { self.error = error.localizedDescription }
    }
}
