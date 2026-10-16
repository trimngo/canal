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
    private var captures: [Capture] {
        let ordered = store.ledger.rankedCaptureIDs
        return store.ledger.captures.filter { $0.deletedAt == nil && $0.isDone == showDone }.sorted {
            if !showDone {
                let a = ordered.firstIndex(of: $0.id), b = ordered.firstIndex(of: $1.id)
                if let a, let b { return a < b }
                if (a != nil) != (b != nil) { return a != nil }
            }
            return $0.createdAt > $1.createdAt
        }
    }
    var body: some View {
        List {
            Section {
                TextField("Get it out of your head…", text: $text, axis: .vertical).lineLimit(1...4)
                    .focused($focused).accessibilityIdentifier("inbox.text")
                Button("Capture") {
                    do { try store.addCapture(text); text = ""; focused = false } catch { store.report(error) }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                    .accessibilityIdentifier("inbox.save")
            }
            if !showDone {
                Section {
                    let ranked = store.ledger.rankedCaptureIDs.count
                    let waiting = store.ledger.activeCaptures.count - ranked
                    Text(waiting == 0 ? "All ideas ranked" : "\(ranked) ranked · \(waiting) waiting to rank")
                        .foregroundStyle(.secondary).accessibilityIdentifier("inbox.ranking-status")
                    if waiting > 0 {
                        Button(store.ledger.rankingPair == nil ? "Rank ideas" : "Continue ranking") {
                            do { try store.prepareRanking(); focused = false; ranking = true } catch { store.report(error) }
                        }.accessibilityIdentifier("inbox.rank")
                    }
                }
            }
            if store.canUndoCaptureDeletion {
                Section { Button("Undo deletion") { store.undoCaptureDeletion() }.accessibilityIdentifier("inbox.undo-delete") }
            }
            Section {
                Toggle("Show completed", isOn: $showDone)
                if captures.isEmpty { Text(showDone ? "No completed captures." : "Capture an idea above.").foregroundStyle(.secondary) }
                ForEach(captures) { capture in
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
            }
            Section("Hands-free capture") {
                Text("Idea: ‘Siri, create a note in Dash called idea, try shorter lessons.’\nActivity: ‘Siri, create a note in Dash called doing, preparing class.’ Say the whole entry in one sentence.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.scrollDismissesKeyboard(.immediately).ledgerInputDismissal()
            .onDisappear { focused = false }.navigationTitle("Inbox").sheet(isPresented: $ranking) { RankingView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
        if let rank = store.ledger.rankedCaptureIDs.firstIndex(of: capture.id) { return "#\(rank + 1) · \(date)" }
        return showDone ? date : "Waiting to rank · \(date)"
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
