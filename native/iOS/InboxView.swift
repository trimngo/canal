import SwiftUI
import UIKit
import LedgerCore

struct InboxView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = Date()
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var showDone = false
    @State private var ranking = false
    @State private var showBacklog = false
    @State private var showSnoozed = false
    @State private var editing: Capture?
    @State private var snoozing: Capture?
    @State private var copiedIdeaCount: Int?
    private var snoozed: [Capture] { store.ledger.snoozedCaptures(at: clock) }
    private var ranked: [Capture] { store.ledger.rankedCaptures }
    private var waiting: [Capture] { store.ledger.unseenCaptures }
    private var inProgress: [Capture] { store.ledger.partiallyRankedCaptures }
    private var backlog: [Capture] { store.ledger.backlogCaptures }
    private var rankButtonTitle: String {
        if store.ledger.rankingIsActive { return "Continue ranking" }
        let count = waiting.count
        return "Rank \(count) new \(count == 1 ? "idea" : "ideas")"
    }
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
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                        .accessibilityIdentifier("inbox.save")
                }
                if store.canUndoCaptureDeletion {
                    Section { Button("Undo deletion") { store.undoCaptureDeletion() }.accessibilityIdentifier("inbox.undo-delete") }
                }
                if showDone {
                    Section("Completed (\(completed.count))") {
                        if completed.isEmpty { Text("No completed captures.").foregroundStyle(.secondary) }
                        ForEach(completed) { captureRow($0) }
                    }
                } else {
                    Section {
                        if ranked.isEmpty { Text("Your highest priorities will appear here when you choose to rank ideas.").foregroundStyle(.secondary) }
                        ForEach(ranked) { captureRow($0) }
                        if store.ledger.needsTopTenReplenishment {
                            Button(store.ledger.rankingIsActive ? "Continue ranking" : "Review backlog to refill priorities") {
                                do { try store.replenishTopTen(); focused = false; ranking = true } catch { store.report(error) }
                            }.accessibilityIdentifier("inbox.replenish")
                        }
                    } header: {
                        Text("Top 10 Priorities (\(ranked.count))").textCase(nil).font(.headline).accessibilityIdentifier("inbox.ranked-title")
                    } footer: {
                        Text(rankingStatus).accessibilityIdentifier("inbox.ranking-status")
                    }
                    Section {
                        if waiting.isEmpty {
                            Text("No new ideas to review.").foregroundStyle(.secondary).id("inbox.waiting")
                        } else {
                            Button(rankButtonTitle) {
                                do { try store.prepareRanking(); focused = false; ranking = true } catch { store.report(error) }
                            }.accessibilityIdentifier("inbox.rank").id("inbox.waiting")
                            ForEach(waiting) { captureRow($0) }
                        }
                    } header: {
                        Text("New Ideas (\(waiting.count))").textCase(nil).font(.headline).accessibilityIdentifier("inbox.waiting-title")
                    } footer: {
                        Text("Ideas you haven't seen in a comparison yet.")
                    }
                    if !inProgress.isEmpty {
                        Section {
                            Button("Continue ranking") {
                                do { try store.prepareRanking(); focused = false; ranking = true } catch { store.report(error) }
                            }.accessibilityIdentifier("inbox.continue")
                            ForEach(inProgress) { captureRow($0) }
                        } header: {
                            Text("In progress (\(inProgress.count))").textCase(nil).font(.headline)
                                .accessibilityIdentifier("inbox.progress-title")
                        } footer: {
                            Text("Not yet placed. Continue to finish each idea’s position before moving to another. Your answers are saved.")
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
                        Text("Evaluated ideas outside your current priorities. The backlog is unsorted; you can re-rank any idea.")
                    }
                    Section {
                        DisclosureGroup(isExpanded: $showSnoozed) {
                            if snoozed.isEmpty { Text("No snoozed ideas.").foregroundStyle(.secondary) }
                            ForEach(snoozed) { captureRow($0) }
                        } label: {
                            Text("Snoozed (\(snoozed.count))").accessibilityIdentifier("inbox.snoozed")
                        }
                    } footer: {
                        Text("Soonest return first. Due ideas return to the front of New Ideas for a fresh review.")
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
                Section { Toggle("Show completed", isOn: $showDone) }
                Section("Hands-free capture") {
                    NavigationLink("Set up Siri via Reminders") { ReminderInboxSetupView() }
                        .accessibilityIdentifier("inbox.reminders")
                    Text("Say ‘Siri, remind me to…’ and Dash imports the idea from your connected list. New items appear when you open Dash; background import is best effort.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.scrollDismissesKeyboard(.immediately).ledgerInputDismissal()
                .onDisappear { focused = false }.navigationTitle("Inbox").sheet(isPresented: $ranking) { RankingView() }
                .onChange(of: ranking) { _, presented in
                    if !presented { withAnimation { proxy.scrollTo("inbox.capture", anchor: .top) } }
                }
                .sheet(item: $editing) { CaptureEditView(capture: $0) }
                .sheet(item: $snoozing) { CaptureSnoozeView(capture: $0) }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if !showDone, !waiting.isEmpty {
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
                .task(id: snoozed.first?.snoozedUntil) {
                    guard let due = snoozed.first?.snoozedUntil else { return }
                    do {
                        try await Task.sleep(for: .seconds(max(0, due.timeIntervalSinceNow)))
                        try store.resumeRanking()
                        clock = Date()
                    } catch is CancellationError { } catch { store.report(error) }
                }
        }
    }
    private var rankingStatus: String {
        if waiting.isEmpty, !store.ledger.needsTopTenReplenishment, !store.ledger.rankingIsActive {
            return ranked.isEmpty ? "Capture first. Rank whenever you like." : "Up to date · \(ranked.count) priorities"
        }
        let pending = "\(waiting.count) unseen · \(inProgress.count) in progress."
        if store.ledger.needsTopTenReplenishment {
            return "Provisional · Review the backlog to confirm your highest priorities. " + pending
        }
        return "Provisional · " + pending
    }
    private func captureRow(_ capture: Capture) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                do { try store.setCaptureDone(capture, done: !capture.isDone) } catch { store.report(error) }
            } label: { Image(systemName: capture.isDone ? "checkmark.circle.fill" : "circle").font(.title3).frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel(capture.isDone ? "Reopen capture" : "Complete capture")
            VStack(alignment: .leading, spacing: 6) {
                Text(capture.text).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .onTapGesture { focused = false; editing = capture }
                    .accessibilityAction(named: "Edit idea") { focused = false; editing = capture }
                    .accessibilityIdentifier("inbox.details.\(capture.id)")
                Text(metadata(capture)).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Edit idea") { focused = false; editing = capture }
                if !capture.isDone {
                    if capture.isReference == true {
                        Button("Move to New Ideas") { moveReference(capture, reference: false) }
                    } else {
                        Button("Move to Reference") { moveReference(capture, reference: true) }
                        if capture.isSnoozed(at: Date()) {
                            Button("Bring back now") { bringBack(capture) }
                        }
                        Button(capture.isSnoozed(at: Date()) ? "Change return date…" : "Snooze…") { focused = false; snoozing = capture }
                        if !capture.isSnoozed(at: Date()) {
                            Button("Re-rank this idea") {
                                do { try store.rerankCapture(capture.id); ranking = true } catch { store.report(error) }
                            }
                        }
                    }
                }
                Button("Delete idea", role: .destructive) { remove(capture) }
            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(.borderless).accessibilityLabel("Idea actions")
                .accessibilityIdentifier("inbox.actions.\(capture.id)")
        }.padding(.vertical, 4)
            .swipeActions { Button("Delete", role: .destructive) { remove(capture) } }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if !capture.isDone, capture.isReference != true {
                    if capture.isSnoozed(at: Date()) {
                        Button("Bring back", systemImage: "arrow.uturn.backward") { bringBack(capture) }.tint(.teal)
                    } else {
                        Button("Snooze", systemImage: "moon.zzz") { focused = false; snoozing = capture }.tint(.indigo)
                    }
                }
            }
    }
    private func copyIdeas() {
        let export = store.ledger.inboxExport
        guard export.count > 0 else { return }
        UIPasteboard.general.string = export.text
        copiedIdeaCount = export.count
        focused = false
    }
    private func remove(_ capture: Capture) { do { try store.deleteCapture(capture) } catch { store.report(error) } }
    private func bringBack(_ capture: Capture) { do { try store.bringBackCapture(capture) } catch { store.report(error) } }
    private func moveReference(_ capture: Capture, reference: Bool) {
        do { try store.setCaptureReference(capture, reference: reference) } catch { store.report(error) }
    }
    private func metadata(_ capture: Capture) -> String {
        let date = "\(capture.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(store.time(capture.createdAt))"
        let origin = (store.ledger.reminderImports ?? []).contains { $0.captureID == capture.id } ? "From Reminders · " : ""
        if capture.isReference == true { return "Reference · \(origin)\(date)" }
        if let due = capture.snoozedUntil, !capture.isDone {
            if due > Date() { return "Returns \(due.formatted(date: .abbreviated, time: .shortened))" }
            if waiting.contains(where: { $0.id == capture.id }) { return "Back from snooze · \(origin)\(date)" }
        }
        if let rank = store.ledger.rankedCaptureIDs.firstIndex(of: capture.id) { return "#\(rank + 1) · \(origin)\(date)" }
        if showDone { return origin + date }
        let status = backlog.contains { $0.id == capture.id } ? "Backlog" : inProgress.contains { $0.id == capture.id } ? "In progress" : "Unseen"
        return "\(origin)\(status) · \(date)"
    }
}

private struct CaptureEditView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let capture: Capture
    @State private var text: String
    @State private var notes: String

    init(capture: Capture) {
        self.capture = capture
        _text = State(initialValue: capture.text)
        _notes = State(initialValue: capture.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Idea") {
                    TextEditor(text: $text).frame(minHeight: 100).accessibilityIdentifier("capture.edit-text")
                }
                Section("Notes (optional)") {
                    TextEditor(text: $notes).frame(minHeight: 140).accessibilityIdentifier("capture.edit-notes")
                }
                Text("Captured \(capture.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Edit idea").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.immediately).ledgerInputDismissal()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do { try store.updateCapture(capture, text: text, notes: notes); dismiss() } catch { store.report(error) }
                        }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                            .accessibilityIdentifier("capture.edit-save")
                    }
                }
        }
    }
}

private struct CaptureSnoozeView: View {
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
                    DatePicker("Return", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Button("Snooze until this date") { propose(date) }.accessibilityIdentifier("snooze.custom")
                }
                Text("Returns to New Ideas for a fresh review. Your notes and original capture date stay unchanged.")
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
                    Text(due.formatted(date: .abbreviated, time: .shortened))
                }
                .onAppear {
                    if let existing = capture.snoozedUntil, existing > Date() { date = existing }
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

private struct RankingView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var snoozing: Capture?
    @State private var editing: Capture?
    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(spacing: 24) {
                let pair = store.ledger.rankingPair
                if let pair,
                   let first = store.ledger.activeCaptures.first(where: { $0.id == pair.first }),
                   let second = store.ledger.activeCaptures.first(where: { $0.id == pair.second }) {
                    Text("Which is more important to act on now?").font(.title2.bold()).multilineTextAlignment(.center)
                    choice(first, pair: pair, id: "ranking.first")
                    Text("or").foregroundStyle(.secondary)
                    choice(second, pair: pair, id: "ranking.second")
                    Text("Finish placing this idea, then review the next. Every choice is saved; you can pause anytime.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Label("Review complete", systemImage: "checkmark.circle.fill").font(.title2).foregroundStyle(.tint)
                    Text(store.ledger.topTenIsVerified ? "Your priorities are up to date." : "You can review more ideas later. Capture is always available.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if !store.ledger.unrankedCaptures.isEmpty {
                        let count = store.ledger.unrankedCaptures.count
                        Button("Rank \(count) more \(count == 1 ? "idea" : "ideas")") {
                            do { try store.prepareRanking() } catch { store.report(error) }
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("ranking.more")
                    }
                    if store.ledger.needsTopTenReplenishment {
                        Button("Review backlog to refill priorities") {
                            do { try store.replenishTopTen() } catch { store.report(error) }
                        }.accessibilityIdentifier("ranking.replenish")
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
            }.navigationTitle("Rank ideas").navigationBarTitleDisplayMode(.inline)
                .sheet(item: $snoozing) { CaptureSnoozeView(capture: $0) }
                .sheet(item: $editing) { CaptureEditView(capture: $0) }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .task { do { try store.resumeRanking() } catch { store.report(error) } }
                .onChange(of: store.ledger.rankingPair, initial: true) { _, _ in
                    do { try store.markRankingPresented() } catch { store.report(error) }
                }
                .onChange(of: store.ledger.captures) { _, _ in do { try store.resumeRanking() } catch { store.report(error) } }
        }
    }
    private func choice(_ capture: Capture, pair: RankingPair, id: String) -> some View {
        VStack(spacing: 8) {
            Button {
                do { try store.chooseCapture(capture.id, pair: pair) } catch { store.report(error) }
            } label: {
                Text(capture.text).font(.title3).frame(maxWidth: .infinity, minHeight: 90).padding(12)
            }.buttonStyle(.bordered).accessibilityIdentifier(id)
            HStack {
                Button("Snooze", systemImage: "moon.zzz") { snoozing = capture }
                    .accessibilityIdentifier("\(id).snooze")
                Spacer()
                Menu {
                    Button("Edit idea") { editing = capture }.accessibilityIdentifier("\(id).edit")
                    Button("Mark done") {
                        do { try store.setCaptureDone(capture, done: true) } catch { store.report(error) }
                    }.accessibilityIdentifier("\(id).done")
                    Button("Move to Reference") {
                        do { try store.setCaptureReference(capture, reference: true) } catch { store.report(error) }
                    }.accessibilityIdentifier("\(id).reference")
                } label: { Label("More", systemImage: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityIdentifier("\(id).actions")
                Button(role: .destructive) {
                    do { try store.deleteCapture(capture) } catch { store.report(error) }
                } label: { Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.borderless).accessibilityLabel("Delete idea: \(capture.text)")
                    .accessibilityIdentifier("\(id).delete")
            }
        }
    }
}
