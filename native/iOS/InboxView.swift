import SwiftUI
import UIKit
import LedgerCore

struct InboxView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var showDone = false
    @State private var ranking = false
    @State private var copiedIdeaCount: Int?
    private var ranked: [Capture] { store.ledger.rankedCaptures }
    private var waiting: [Capture] { store.ledger.unrankedCaptures }
    private var completed: [Capture] {
        store.ledger.captures.filter { $0.deletedAt == nil && $0.isDone }.sorted { $0.createdAt > $1.createdAt }
    }
    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    TextField("Get it out of your head…", text: $text, axis: .vertical).lineLimit(1...4)
                        .focused($focused).accessibilityIdentifier("inbox.text")
                    Button("Capture") {
                        do { try store.addCapture(text); text = ""; focused = false } catch { store.report(error) }
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                        .accessibilityIdentifier("inbox.save")
                }
                if store.canUndoCaptureDeletion {
                    Section { Button("Undo deletion") { store.undoCaptureDeletion() }.accessibilityIdentifier("inbox.undo-delete") }
                }
                Section {
                    Toggle("Show completed", isOn: $showDone)
                    if !showDone {
                        Text(waiting.isEmpty ? "All ideas ranked" : "\(ranked.count) ranked · \(waiting.count) waiting to rank")
                            .foregroundStyle(.secondary).accessibilityIdentifier("inbox.ranking-status")
                    }
                }
                if showDone {
                    Section("Completed (\(completed.count))") {
                        if completed.isEmpty { Text("No completed captures.").foregroundStyle(.secondary) }
                        ForEach(completed) { captureRow($0) }
                    }
                } else {
                    Section {
                        if ranked.isEmpty { Text("Rank your new ideas to decide what to do next.").foregroundStyle(.secondary) }
                        ForEach(ranked) { captureRow($0) }
                    } header: {
                        Text("Ranked (\(ranked.count))").textCase(nil).font(.headline).accessibilityIdentifier("inbox.ranked-title")
                    }
                    Section {
                        if waiting.isEmpty {
                            Text("No ideas waiting to rank.").foregroundStyle(.secondary).id("inbox.waiting")
                        } else {
                            Button(store.ledger.rankingPair == nil ? "Rank new ideas" : "Continue ranking") {
                                do { try store.prepareRanking(); focused = false; ranking = true } catch { store.report(error) }
                            }.accessibilityIdentifier("inbox.rank").id("inbox.waiting")
                            ForEach(waiting) { captureRow($0) }
                        }
                    } header: {
                        Text("New · waiting to rank (\(waiting.count))").textCase(nil).font(.headline).accessibilityIdentifier("inbox.waiting-title")
                    }
                }
                Section("Hands-free capture") {
                    NavigationLink("Set up Siri via Reminders") { ReminderInboxSetupView() }
                        .accessibilityIdentifier("inbox.reminders")
                    Text("Say ‘Siri, remind me to…’ and Dash imports the idea from your connected list. New items appear when you open Dash; background import is best effort.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.scrollDismissesKeyboard(.immediately).ledgerInputDismissal()
                .onDisappear { focused = false }.navigationTitle("Inbox").sheet(isPresented: $ranking) { RankingView() }
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
                .task { await ReminderInbox.shared.refresh() }
        }
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
        return showDone ? origin + date : "\(origin)Waiting to rank · \(date)"
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
                    Text("Which is more important to act on?").font(.title2.bold()).multilineTextAlignment(.center)
                    choice(first, pair: pair, id: "ranking.first")
                    Text("or").foregroundStyle(.secondary)
                    choice(second, pair: pair, id: "ranking.second")
                    Text("Every choice is saved. You can pause anytime.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Label("All ideas ranked", systemImage: "checkmark.circle.fill").font(.title2).foregroundStyle(.tint)
                    Text("New ideas will wait for a few comparisons to find their place.").foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                .task { do { try store.prepareRanking() } catch { store.report(error) } }
                .onChange(of: store.ledger.captures) { _, _ in do { try store.prepareRanking() } catch { store.report(error) } }
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
