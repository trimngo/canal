import SwiftUI
import UIKit
import LedgerCore

struct InboxView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = Date()
    @State private var text = ""
    @FocusState private var focused: Bool
    @FocusState private var searchFocused: Bool
    @State private var searchText = ""
    @State private var categoryFilter: String?
    @State private var showDone = false
    @State private var ranking = false
    @State private var categorizing: CaptureCategoryReviewRequest?
    @State private var showingCategories = false
    @State private var showBacklog = false
    @State private var showSnoozed = false
    @State private var snoozing: Capture?
    @State private var editingCapture: Capture?
    @State private var copiedIdeaCount: Int?
    private var snoozed: [Capture] { store.ledger.snoozedCaptures(at: clock) }
    private var ranked: [Capture] { store.inbox.ranked }
    private var waiting: [Capture] { store.inbox.unseen }
    private var inProgress: [Capture] { store.inbox.inProgress }
    private var backlog: [Capture] { store.inbox.backlog }
    private var searching: Bool { categoryFilter != nil || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var searchResults: [Capture] { store.ledger.searchInbox(searchText, categoryID: categoryFilter) }
    private var completed: [Capture] {
        store.ledger.captures.filter { $0.deletedAt == nil && $0.isDone }.sorted { $0.createdAt > $1.createdAt }
    }
    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    TextField("Get it out of your head…", text: $text, axis: .vertical).lineLimit(1...4)
                        .focused($focused).accessibilityIdentifier("inbox.text").id("inbox.capture")
                    Button("Save") {
                        do { try store.addCapture(text); text = ""; focused = true } catch { store.report(error) }
                    }.disabled(!store.storageAvailable || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .ledgerPreserveKeyboard()
                        .accessibilityIdentifier("inbox.save")
                }
                Section {
                    HStack {
                        Menu("Categorize ideas", systemImage: "tag") {
                            categoryReviewButton("Uncategorized", uncategorizedOnly: true)
                            categoryReviewButton("All ideas", uncategorizedOnly: false)
                        }.accessibilityIdentifier("inbox.categorize")
                        Spacer()
                        Button("Categories", systemImage: "folder") {
                            endInput(); showingCategories = true
                        }.accessibilityIdentifier("inbox.categories")
                    }
                    Button("Review ideas", systemImage: "arrow.left.arrow.right") { review() }
                        .accessibilityIdentifier("inbox.review")
                        .disabled(store.ledger.activeCaptures.isEmpty || !store.storageAvailable)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search ideas and notes", text: $searchText)
                            .focused($searchFocused)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("inbox.search")
                        if !searchText.isEmpty {
                            Button("Clear search", systemImage: "xmark.circle.fill") { searchText = "" }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                                .accessibilityIdentifier("inbox.search-clear")
                        }
                        Menu {
                            Button("All categories") { categoryFilter = nil }
                            Button("Uncategorized") { categoryFilter = "uncategorized" }
                                .accessibilityIdentifier("inbox.filter.uncategorized")
                            ForEach(store.ledger.orderedCategories) { category in
                                Button(store.ledger.categoryPath(category.id)) { categoryFilter = category.id }
                                    .accessibilityIdentifier("inbox.filter.\(category.id)")
                            }
                        } label: {
                            Image(systemName: categoryFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("Filter ideas by category").accessibilityIdentifier("inbox.category-filter")
                    }
                    if let categoryFilter {
                        Button { self.categoryFilter = nil } label: {
                            Label(store.ledger.categoryPath(categoryFilter), systemImage: "xmark.circle.fill")
                        }.font(.subheadline).accessibilityLabel("Clear category filter").accessibilityIdentifier("inbox.category-filter-clear")
                    }
                }
                if searching {
                    Section {
                        if searchResults.isEmpty { Text("No matching ideas.").foregroundStyle(.secondary) }
                        ForEach(searchResults) { captureRow($0) }
                    } header: {
                        Text("Search results (\(searchResults.count))").accessibilityIdentifier("inbox.search-results")
                    }
                } else if showDone {
                    Section("Completed (\(completed.count))") {
                        if completed.isEmpty { Text("No completed captures.").foregroundStyle(.secondary) }
                        ForEach(completed) { captureRow($0) }
                    }
                } else {
                    let urgent = store.ledger.urgentCaptures(at: clock)
                    if !urgent.isEmpty {
                        Section {
                            ForEach(urgent) { capture in
                                InboxCaptureRow(capture: capture, onEdit: { endInput(); editingCapture = $0 }, onSnooze: {
                                    endInput(); snoozing = $0
                                }, isUrgentSection: true)
                            }
                        } header: {
                            Text("Urgent (\(urgent.count))").textCase(nil).font(.headline)
                                .accessibilityIdentifier("inbox.urgent-title")
                        }
                    }
                    Section {
                        if ranked.isEmpty { Text("Your highest priorities will appear here when you choose to rank ideas.").foregroundStyle(.secondary) }
                        ForEach(ranked) { captureRow($0) }

                    } header: {
                        Text("Top \(InboxRanking.priorityLimit) Priorities (\(ranked.count))").textCase(nil).font(.headline).accessibilityIdentifier("inbox.ranked-title")
                    } footer: {
                        Text(rankingStatus).accessibilityIdentifier("inbox.ranking-status")
                    }
                    Section {
                        if waiting.isEmpty {
                            Text("No new ideas to review.").foregroundStyle(.secondary).id("inbox.waiting")
                        } else {
                            Color.clear.frame(height: 0).id("inbox.waiting")
                            ForEach(waiting) { captureRow($0) }
                        }
                    } header: {
                        Text("New Ideas (\(waiting.count))").textCase(nil).font(.headline).accessibilityIdentifier("inbox.waiting-title")
                    } footer: {
                        Text("Ideas you haven't seen in a comparison yet. Review starts with the newest arrivals.")
                    }
                    if !inProgress.isEmpty {
                        Section {
                            ForEach(inProgress) { captureRow($0) }
                        } header: {
                            Text("In progress (\(inProgress.count))").textCase(nil).font(.headline)
                                .accessibilityIdentifier("inbox.progress-title")
                        } footer: {
                            Text("Every answer stays saved. New ideas are screened against your priorities. You can pause anytime.")
                        }
                    }
                    Section {
                        DisclosureGroup(isExpanded: $showBacklog) {
                            if backlog.isEmpty { Text("No backlog ideas yet.").foregroundStyle(.secondary) }
                            ForEach(backlog) { captureRow($0) }
                        } label: {
                            Text("Backlog (\(backlog.count))").accessibilityIdentifier("inbox.backlog")
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Optional review, oldest reviewed first. New ideas always come first.")
                            if let oldest = store.inbox.oldestBacklogReview {
                                Text("Oldest backlog review: \(oldest.formatted(.relative(presentation: .numeric)))")
                                    .accessibilityIdentifier("inbox.backlog-oldest-review")
                            }
                            if store.inbox.backlogWithoutReviewDateCount > 0 {
                                Text("\(store.inbox.backlogWithoutReviewDateCount) without a recorded review date.")
                                    .accessibilityIdentifier("inbox.backlog-undated")
                            }
                        }
                    }
                    Section {
                        DisclosureGroup(isExpanded: $showSnoozed) {
                            if snoozed.isEmpty { Text("No snoozed ideas.").foregroundStyle(.secondary) }
                            ForEach(snoozed) { captureRow($0) }
                        } label: {
                            Text("Snoozed (\(snoozed.count))").accessibilityIdentifier("inbox.snoozed")
                        }
                    } footer: {
                        Text("Soonest return first. Ideas return at 8 a.m. on the chosen date and join New Ideas in arrival order.")
                    }
                    Section {
                        if store.ledger.referenceCaptures.isEmpty {
                            Text("Keep useful notes here when there's no action to take.").foregroundStyle(.secondary)
                        }
                        ForEach(store.ledger.referenceCaptures) { captureRow($0) }
                    } header: {
                        Text("Reference (\(store.ledger.referenceCaptures.count))").textCase(nil).font(.headline)
                            .accessibilityIdentifier("inbox.reference-title")
                    } footer: {
                        Text("Reference items stay out of ranking. Move one back to New Ideas if it needs action.")
                    }
                }
                if !searching { Section { Toggle("Show completed", isOn: $showDone) } }
                Section("Hands-free capture") {
                    NavigationLink("Set up Siri via Reminders") { ReminderInboxSetupView() }
                        .accessibilityIdentifier("inbox.reminders")
                    Text("Say ‘Siri, remind me to…’ and Dash imports the idea from your connected list. New items appear when you open Dash; background import is best effort.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.scrollDismissesKeyboard(.immediately).ledgerInputDismissal()
                .safeAreaInset(edge: .bottom, spacing: 0) { CaptureDeletionUndoBar() }
                .onDisappear { focused = false; searchFocused = false }.navigationTitle("Inbox").sheet(isPresented: $ranking) { RankingView() }
                .onChange(of: ranking) { _, presented in
                    if !presented { withAnimation { proxy.scrollTo("inbox.capture", anchor: .top) } }
                }
                .sheet(item: $snoozing) { CaptureSnoozeView(capture: $0) }
                .sheet(item: $editingCapture) { TaskPlanningView(capture: $0) }
                .sheet(item: $categorizing) { CaptureCategoryReviewView(captureIDs: $0.captureIDs) }
                .sheet(isPresented: $showingCategories) { InboxCategoriesView() }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if !showDone, !searching, !waiting.isEmpty {
                            Button("New \(waiting.count)") {
                                focused = false
                                withAnimation { proxy.scrollTo("inbox.waiting", anchor: UnitPoint(x: 0.5, y: 0.15)) }
                            }.accessibilityIdentifier("inbox.new-shortcut")
                                .accessibilityLabel("\(waiting.count) new ideas waiting to rank")
                        }
                        Button("Copy all ideas", systemImage: "doc.on.doc", action: copyIdeas)
                            .accessibilityIdentifier("inbox.copy-all")
                            .disabled(!store.ledger.captures.contains { $0.deletedAt == nil })
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let copiedIdeaCount {
                        Text("Copied \(copiedIdeaCount) \(copiedIdeaCount == 1 ? "idea" : "ideas"), including completed ideas")
                            .font(.footnote).padding(12).frame(maxWidth: .infinity).background(.regularMaterial)
                            .accessibilityIdentifier("inbox.copy-confirmation")
                    }
                }
                .task(id: copiedIdeaCount) {
                    guard copiedIdeaCount != nil else { return }
                    do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
                    copiedIdeaCount = nil
                }
                .task {
                    await Task.yield(); focused = true
                    do { try store.resumeRanking() } catch { store.report(error) }
                    await ReminderInbox.shared.refresh()
                }
                .onChange(of: store.ledger.captures) { _, _ in clock = Date() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { clock = Date() } }
                .task(id: snoozed.first?.snoozeReturnDate()) {
                    guard let due = snoozed.first?.snoozeReturnDate() else { return }
                    do {
                        try await Task.sleep(for: .seconds(max(0, due.timeIntervalSinceNow)))
                        try store.resumeRanking()
                        clock = Date()
                    } catch is CancellationError { } catch { store.report(error) }
                }
        }
    }
    private func endInput() { focused = false; searchFocused = false; UIApplication.shared.dismissLedgerKeyboard() }
    private func categoryReviewButton(_ title: String, uncategorizedOnly: Bool) -> some View {
        let ids = store.ledger.inboxCategorizationIDs(uncategorizedOnly: uncategorizedOnly)
        return Button("\(title) (\(ids.count))") {
            endInput(); categorizing = CaptureCategoryReviewRequest(captureIDs: ids)
        }.disabled(ids.isEmpty || !store.storageAvailable)
            .accessibilityIdentifier(uncategorizedOnly ? "inbox.categorize-uncategorized" : "inbox.categorize-all")
    }
    private func review() {
        do { try store.prepareRanking(); focused = false; searchFocused = false; ranking = true } catch { store.report(error) }
    }
    private var rankingStatus: String {
        let count = waiting.count + inProgress.count
        if count > 0 { return "\(count) ideas waiting for review · Newest first. Your priorities stay available." }
        return backlog.isEmpty ? "Capture first. Review whenever you like." :
            "New ideas reviewed. Backlog review is optional; this list isn't a verified ranking of every idea."
    }
    private func captureRow(_ capture: Capture) -> some View {
        InboxCaptureRow(capture: capture, onEdit: { endInput(); editingCapture = $0 }, onSnooze: {
            focused = false; searchFocused = false; snoozing = $0
        })
    }
    private func copyIdeas() {
        let export = store.ledger.inboxExport
        guard export.count > 0 else { return }
        UIPasteboard.general.string = export.text
        copiedIdeaCount = export.count
        focused = false; searchFocused = false
    }

}

struct InboxCaptureRow: View {
    @EnvironmentObject private var store: LedgerStore
    let capture: Capture
    let onEdit: (Capture) -> Void
    let onSnooze: (Capture) -> Void
    var isUrgentSection = false
    private var prefix: String { isUrgentSection ? "inbox.urgent" : "inbox" }
    private var urgency: InboxUrgency? { store.ledger.urgency(for: capture) }
    private var categoryNames: [String] {
        store.ledger.categoryIDs(for: capture).map { store.categoryName($0) }
    }
    private var hasNotes: Bool { !(capture.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                do { try store.setCaptureDone(capture, done: !capture.isDone) } catch { store.report(error) }
            } label: {
                Image(systemName: capture.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3).frame(width: 32, height: 44)
            }.buttonStyle(.borderless).accessibilityLabel(capture.isDone ? "Reopen capture" : "Complete capture")
                .accessibilityIdentifier("\(prefix).complete.\(capture.id)")
            VStack(alignment: .leading, spacing: 3) {
                InlineEntryText(text: capture.text, identifier: "\(prefix).details.\(capture.id)") {
                    try store.updateCaptureText(capture, text: $0)
                }
                Button { onEdit(capture) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(summary).font(.caption).foregroundStyle(urgency == nil ? Color.secondary : .orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if hasNotes {
                                Image(systemName: "note.text").font(.caption).foregroundStyle(.secondary)
                                    .accessibilityLabel("Has notes").accessibilityIdentifier("\(prefix).has-notes.\(capture.id)")
                            }
                        }
                        // The category line gets the entire content width. Prefer
                        // full short names over breadcrumbs; overflow is counted,
                        // rather than showing a cut-off category name.
                        ViewThatFits(in: .horizontal) {
                            Text(categoryLabel(categoryNames)).fixedSize(horizontal: true, vertical: false)
                            if let first = categoryNames.first, categoryNames.count > 1 {
                                Text(categoryLabel([first]) + " +\(categoryNames.count - 1)")
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            } else {
                                Text(categoryLabel(categoryNames)).lineLimit(1).minimumScaleFactor(0.75)
                            }
                        }.font(.caption).foregroundStyle(capture.categorySuggestion == nil ? Color.secondary : .orange)
                            .accessibilityLabel(categoryLabel(categoryNames))
                            .accessibilityIdentifier("\(prefix).categories.\(capture.id)")
                    }.frame(maxWidth: .infinity, minHeight: 28, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint("Open all item details")
                    .accessibilityIdentifier("\(prefix).edit.\(capture.id)")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 2)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    do { try store.deleteCapture(capture) } catch { store.report(error) }
                }.accessibilityIdentifier("\(prefix).delete.\(capture.id)")
                if !capture.isDone {
                    Button(capture.isReference == true ? "To Inbox" : "Reference", systemImage: "archivebox") {
                        do { try store.setCaptureReference(capture, reference: capture.isReference != true) } catch { store.report(error) }
                    }.tint(.teal).accessibilityIdentifier("\(prefix).reference.\(capture.id)")
                    if capture.isReference != true {
                        Button("Snooze", systemImage: "moon.zzz") { onSnooze(capture) }
                            .tint(.indigo).accessibilityIdentifier("\(prefix).snooze.\(capture.id)")
                    }
                }
            }
    }
    private func categoryLabel(_ names: [String]) -> String {
        let label = names.isEmpty ? "Uncategorized" : names.joined(separator: " · ")
        return (capture.categorySuggestion == nil ? "" : "Suggested: ") + label
    }
    private var summary: String {
        var parts: [String] = []
        if capture.isDone { parts.append("Completed") }
        else if capture.isReference == true { parts.append("Reference") }
        else if capture.isSnoozed(at: Date()), let due = capture.snoozeReturnDate() {
            parts.append("Returns " + due.formatted(date: .abbreviated, time: .omitted))
        } else if let rank = store.inbox.ranked.firstIndex(where: { $0.id == capture.id }) { parts.append("#\(rank + 1)") }
        else if store.inbox.backlog.contains(where: { $0.id == capture.id }) { parts.append("Backlog") }
        else if store.inbox.inProgress.contains(where: { $0.id == capture.id }) { parts.append("In progress") }
        else { parts.append("Unseen") }
        if let urgency {
            if let date = urgency.timing.dueAt { parts.append("Due " + date.formatted(date: .abbreviated, time: .omitted)) }
            else { parts.append(urgency.isSuggested ? "Suggested ASAP" : "ASAP") }
        }
        if let estimate = capture.workPlan?.estimatedMinutes { parts.append(store.duration(estimate) + " est.") }
        return parts.joined(separator: " · ")
    }
}

struct CaptureDeletionUndoBar: View {
    @EnvironmentObject private var store: LedgerStore
    var body: some View {
        if store.canUndoCaptureDeletion {
            HStack {
                Label("Idea deleted", systemImage: "trash")
                Spacer()
                Button("Undo") { store.undoCaptureDeletion() }.fontWeight(.semibold).buttonStyle(.borderless)
                    .accessibilityIdentifier("inbox.undo-delete")
            }.font(.subheadline).padding(12).background(.regularMaterial)
                .accessibilityElement(children: .contain)
        }
    }
}

struct InlineCaptureNotes: View {
    @EnvironmentObject private var store: LedgerStore
    let capture: Capture
    let identifier: String
    @State private var expanded: Bool
    init(capture: Capture, identifier: String, initiallyExpanded: Bool = false) {
        self.capture = capture; self.identifier = identifier; _expanded = State(initialValue: initiallyExpanded)
    }
    private var current: Capture { store.ledger.captures.first { $0.id == capture.id } ?? capture }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { expanded.toggle() } label: {
                HStack {
                    Text("Notes").font(.caption)
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2)
                }.foregroundStyle(.secondary).frame(minHeight: 32).contentShape(Rectangle())
            }.buttonStyle(.borderless).accessibilityIdentifier("\(identifier).expand")
                .accessibilityLabel(expanded ? "Collapse notes" : "Expand notes")
            if expanded {
                InlineEntryText(text: current.notes ?? "", identifier: identifier, allowEmpty: true) { notes in
                    try store.updateCapture(capture, text: current.text, notes: notes)
                }.padding(.vertical, 6)
            }
        }.accessibilityElement(children: .contain)
    }
}

struct CaptureSnoozeView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let capture: Capture
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var days = "7"
    @State private var weekendDate: Date?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(capture.text)
                    Button("Tomorrow") { snooze(days: 1) }.accessibilityIdentifier("snooze.tomorrow")
                    Button("In a week") { snooze(days: 7) }.accessibilityIdentifier("snooze.week")
                    Button("Next weekday") {
                        if let due = InboxSnooze.nextWeekday(after: Date()) { save(due) }
                    }.accessibilityIdentifier("snooze.weekday")
                }
                Section("Number of days") {
                    TextField("Days", text: $days).keyboardType(.numberPad).accessibilityIdentifier("snooze.days")
                    Button("Snooze for this many days") {
                        if let count = Int(days) { snooze(days: count) }
                    }.disabled(Int(days).map { $0 <= 0 } ?? true).accessibilityIdentifier("snooze.days-save")
                }
                Section("Choose a return date") {
                    DatePicker("Return", selection: $date, in: (InboxSnooze.after(days: 1, from: Date()) ?? Date())..., displayedComponents: [.date])
                    Button("Snooze until this date") { propose(date) }.accessibilityIdentifier("snooze.custom")
                }
                Text("Returns at 8 a.m. on the selected day for a fresh review. Your notes and original capture date stay unchanged.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Snooze idea").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.immediately).ledgerInputDismissal()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .confirmationDialog("This return date is on a weekend", isPresented: Binding(
                    get: { weekendDate != nil }, set: { if !$0 { weekendDate = nil } }
                ), titleVisibility: .visible, presenting: weekendDate) { due in
                    Button("Move to Monday") { save(InboxSnooze.weekdayOnOrAfter(due)) }
                        .accessibilityIdentifier("snooze.move-monday")
                    Button("Keep chosen date") { save(due) }.accessibilityIdentifier("snooze.keep-weekend")
                    Button("Cancel", role: .cancel) { weekendDate = nil }
                } message: { due in
                    Text(due.formatted(date: .abbreviated, time: .omitted))
                }
                .onAppear {
                    if let existing = capture.snoozeReturnDate(), existing > Date() { date = existing }
                }
        }
    }
    private func snooze(days: Int) {
        guard let due = InboxSnooze.after(days: days, from: Date()) else { return }
        propose(due)
    }
    private func propose(_ date: Date) {
        if InboxSnooze.isWeekend(date) { weekendDate = date } else { save(date) }
    }
    private func save(_ date: Date) {
        do { try store.snoozeCapture(capture, until: date); dismiss() } catch { store.report(error) }
    }
}

struct RankingView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var snoozing: Capture?
    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(spacing: 24) {
                let pair = store.inbox.pair
                if let pair,
                   let first = store.ledger.activeCaptures.first(where: { $0.id == pair.first }),
                   let second = store.ledger.activeCaptures.first(where: { $0.id == pair.second }) {
                    Text("Which is more important to act on now?").font(.title2.bold()).multilineTextAlignment(.center)
                    choice(first, pair: pair, id: "ranking.first")
                    Text("or").foregroundStyle(.secondary)
                    choice(second, pair: pair, id: "ranking.second")
                    Text(store.inbox.reviewingBacklog && store.inbox.unrankedCount == 0 ?
                         "Optional backlog review · Oldest reviewed first" :
                         "\(store.inbox.unrankedCount) new ideas left to review")
                        .font(.subheadline).accessibilityIdentifier("ranking.review-progress")
                    Text("One comparison can send an idea to the backlog. A winner takes a few more to find its place. Every answer is saved; stop anytime.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Label("Review complete", systemImage: "checkmark.circle.fill").font(.title2).foregroundStyle(.tint)
                    Text(store.inbox.unrankedCount > 0 ? "Review your newest ideas whenever you're ready." :
                         "New ideas reviewed. You can stop here; your priorities are ready to use.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if store.inbox.unrankedCount > 0 || !store.inbox.backlog.isEmpty {
                        Button(store.inbox.unrankedCount > 0 ? "Review new ideas" : "Review oldest backlog ideas") {
                            do { try store.prepareRanking() } catch { store.report(error) }
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("ranking.more")
                    }
                }
                if store.canUndoCaptureDeletion {
                    HStack {
                        Text("Idea deleted")
                        Spacer()
                        Button("Undo") { store.undoCaptureDeletion() }.accessibilityIdentifier("ranking.undo-delete")
                    }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
                Spacer(minLength: 0)
              }.padding(24)
            }.ledgerInputDismissal().navigationTitle("Rank ideas").navigationBarTitleDisplayMode(.inline)
                .sheet(item: $snoozing) { CaptureSnoozeView(capture: $0) }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .task { do { try store.resumeRanking() } catch { store.report(error) } }
                .onChange(of: store.inbox.pair, initial: true) { _, _ in
                    do { try store.markRankingPresented() } catch { store.report(error) }
                }
                .onChange(of: store.ledger.captures) { _, _ in do { try store.resumeRanking() } catch { store.report(error) } }
        }
    }
    private func choice(_ capture: Capture, pair: RankingPair, id: String) -> some View {
        VStack(spacing: 8) {
            InlineEntryText(text: capture.text, identifier: "\(id).text", font: .title3) {
                try store.updateCaptureText(capture, text: $0)
            }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.4)))
            Button {
                do { try store.chooseCapture(capture.id, pair: pair) } catch { store.report(error) }
            } label: {
                Text("Choose this").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent).accessibilityIdentifier(id)
                .accessibilityLabel("Choose: \(capture.text)")
            CaptureCategoryButton(capture: capture, identifier: "\(id).category")
            InlineCaptureNotes(capture: capture, identifier: "\(id).notes")
            CaptureReviewActions(capture: capture, identifier: id, onSnooze: { snoozing = $0 })
        }.id(capture.id)
    }
}
