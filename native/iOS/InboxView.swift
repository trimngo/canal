import SwiftUI
import UIKit
import LedgerCore

struct InboxView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var showDone = false
    @State private var ranking = false
    @State private var showBacklog = false
    @State private var editing: Capture?
    @State private var copiedIdeaCount: Int?
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
                            Text("Already seen, but not fully ranked. Your answers are saved; unseen ideas get a first look before these are finished.")
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
        }
    }
    private var rankingStatus: String {
        if waiting.isEmpty, !store.ledger.needsTopTenReplenishment, !store.ledger.rankingIsActive {
            return ranked.isEmpty ? "Capture first. Rank whenever you like." : "Up to date · \(ranked.count) priorities"
        }
        if store.ledger.needsTopTenReplenishment {
            return "Provisional · Review the backlog to confirm your highest priorities. \(waiting.count) new ideas not yet reviewed."
        }
        return "Provisional · \(waiting.count) new ideas not yet reviewed."
    }
    private func captureRow(_ capture: Capture) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                do { try store.setCaptureDone(capture, done: !capture.isDone) } catch { store.report(error) }
            } label: { Image(systemName: capture.isDone ? "checkmark.circle.fill" : "circle").font(.title3).frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel(capture.isDone ? "Reopen capture" : "Complete capture")
            VStack(alignment: .leading, spacing: 6) {
                Text(capture.text)
                Text(metadata(capture)).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Edit idea") { focused = false; editing = capture }
                if !capture.isDone {
                    Button("Re-rank this idea") {
                        do { try store.rerankCapture(capture.id); ranking = true } catch { store.report(error) }
                    }
                }
                Button("Delete idea", role: .destructive) { remove(capture) }
            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(.borderless).accessibilityLabel("Idea actions")
                .accessibilityIdentifier("inbox.actions.\(capture.id)")
        }.padding(.vertical, 4)
            .swipeActions { Button("Delete", role: .destructive) { remove(capture) } }
    }
    private func copyIdeas() {
        let export = store.ledger.inboxExport
        guard export.count > 0 else { return }
        UIPasteboard.general.string = export.text
        copiedIdeaCount = export.count
        focused = false
    }
    private func remove(_ capture: Capture) { do { try store.deleteCapture(capture) } catch { store.report(error) } }
    private func metadata(_ capture: Capture) -> String {
        let date = "\(capture.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(store.time(capture.createdAt))"
        let origin = (store.ledger.reminderImports ?? []).contains { $0.captureID == capture.id } ? "From Reminders · " : ""
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

    init(capture: Capture) {
        self.capture = capture
        _text = State(initialValue: capture.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $text).frame(minHeight: 160).accessibilityIdentifier("capture.edit-text")
                Text("Captured \(capture.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Edit idea").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.immediately).ledgerInputDismissal()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do { try store.updateCaptureText(capture, text: text); dismiss() } catch { store.report(error) }
                        }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                            .accessibilityIdentifier("capture.edit-save")
                    }
                }
        }
    }
}

private struct RankingView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
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
                    Text("Every choice is saved. You can pause anytime.").font(.footnote).foregroundStyle(.secondary)
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
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .task { do { try store.resumeRanking() } catch { store.report(error) } }
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
                Spacer()
                Button(role: .destructive) {
                    do { try store.deleteCapture(capture) } catch { store.report(error) }
                } label: { Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.borderless).accessibilityLabel("Delete idea: \(capture.text)")
                    .accessibilityIdentifier("\(id).delete")
            }
        }
    }
}
