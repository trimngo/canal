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
    @State private var calendarActivityText = ""
    @State private var error: String?
    @State private var calendarSuggestion: CategorySuggestion?
    @State private var matchingCalendar = false
    @State private var categoriesWereEdited = false
    private struct CalendarSuggestionRequest: Hashable {
        let eventID: String
        let text: String
    }
    private var categorySelection: Binding<[String]> {
        Binding(get: { categories }, set: { categories = $0; categoriesWereEdited = true })
    }
    private var calendarSuggestionRequest: CalendarSuggestionRequest? {
        event.map { CalendarSuggestionRequest(eventID: $0.id, text: OfflineGrouping.normalized(activityDraft)) }
    }
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
                    CategorySelectionList(selection: categorySelection, activity: event == nil ? entry.activity : calendarActivityText, timestamp: entry.end, mood: $mood,
                        saveActivity: {
                            if event == nil { try store.updateLogActivity(id: entry.id, activity: $0) }
                            else { calendarActivityText = $0 }
                        },
                        activityDraft: Binding(get: { activityDraft }, set: { if current?.id == entry.id { activityDraft = $0 } }), showsKeyboardDone: false)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            VStack(alignment: .leading, spacing: 6) {
                                if let event {
                                    let end = store.ledger.calendarEventEnd(event.snapshot)
                                    Text("Did this happen? · \(event.snapshot.calendarName)").font(.subheadline.bold())
                                    let endLabel = store.ledger.reportingCalendar().isDate(event.snapshot.start, inSameDayAs: end) ? store.time(end) : store.dayLabel(end) + " " + store.time(end)
                                    Text("\(store.dayLabel(event.snapshot.start)) \(store.time(event.snapshot.start))–\(endLabel) · \(store.duration(max(0, end.timeIntervalSince(event.snapshot.start) / 60)))")
                                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("log-review.calendar-period")
                                    if end < event.snapshot.end { Text("Ends at your first overlapping log. That log takes over from there.").font(.caption).foregroundStyle(.secondary) }
                                }
                                if let suggestion = event == nil ? entry.categorySuggestion : calendarSuggestion {
                                    Label("Suggested · \(suggestion.reason)", systemImage: "sparkle").font(.caption).foregroundStyle(.secondary)
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel("Suggested · \(suggestion.reason)")
                                        .accessibilityIdentifier("log-review.suggestion")
                                }
                                LogTaskPicker(goalID: $goalID, categoryIDs: categorySelection)
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
                        .id(item?.id)
                } else { Color.clear }
            }
            .navigationTitle("Review logs").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("log-review.close") }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(event == nil ? "Save & next" : "Confirm & next") { saveAndAdvance() }
                        .disabled(current == nil || !store.storageAvailable || (event != nil && matchingCalendar && !categoriesWereEdited))
                        .accessibilityIdentifier("log-review.save-next")
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
            .task(id: calendarSuggestionRequest) {
                guard let request = calendarSuggestionRequest else { return }
                matchingCalendar = true; calendarSuggestion = nil
                if !categoriesWereEdited { categories = [] }
                do {
                    try await Task.sleep(for: .milliseconds(150))
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-calendar-matching-delay") {
                        try await Task.sleep(for: .seconds(5))
                    }
                    #endif
                } catch { return }
                let suggestion = await AutomaticCategories.shared.suggestion(for: request.text, in: store.ledger)
                guard !Task.isCancelled, request == calendarSuggestionRequest else { return }
                calendarSuggestion = suggestion
                // A late result or edited title must never replace the user's
                // selected categories, including an explicit Uncategorized.
                if !categoriesWereEdited { categories = suggestion?.categoryIDs ?? [] }
                matchingCalendar = false
            }
        }
    }
    private func loadCurrent() {
        while index < queue.count, current == nil { index += 1 }
        guard let entry = current else { if loaded { dismiss() }; return }
        categories = store.ledger.effectiveCategoryIDs(for: entry)
        calendarSuggestion = nil; matchingCalendar = event != nil; categoriesWereEdited = false
        mood = entry.mood; goalID = entry.goalID; activityDraft = entry.activity; calendarActivityText = entry.activity; error = nil
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
