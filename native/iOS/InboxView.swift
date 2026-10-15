import SwiftUI
import LedgerCore

struct InboxView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var text = ""
    @State private var showDone = false
    @State private var ranking = false
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
                    .accessibilityIdentifier("inbox.text")
                Button("Capture") {
                    do { try store.addCapture(text); text = "" } catch { store.report(error) }
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
                            do { try store.prepareRanking(); ranking = true } catch { store.report(error) }
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
                        } label: { Image(systemName: capture.isDone ? "checkmark.circle.fill" : "circle").font(.title3) }
                            .buttonStyle(.borderless).accessibilityLabel(capture.isDone ? "Reopen capture" : "Complete capture")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(capture.text)
                            HStack {
                                if let rank = store.ledger.rankedCaptureIDs.firstIndex(of: capture.id) { Text("#\(rank + 1)") }
                                else if !showDone { Text("Waiting to rank") }
                                Text("\(capture.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(store.time(capture.createdAt))")
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Menu {
                            if !capture.isDone {
                                Button("Re-rank this idea") {
                                    do { try store.rerankCapture(capture.id); ranking = true } catch { store.report(error) }
                                }
                            }
                            Button("Delete idea", role: .destructive) { remove(capture) }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .accessibilityIdentifier("inbox.actions.\(capture.id)")
                    }.padding(.vertical, 4)
                        .swipeActions { Button("Delete", role: .destructive) { remove(capture) } }
                }
            }
            Section("Hands-free capture") {
                Text("Try: ‘Siri, create a note in Ledger called try shorter lessons.’ Say the whole thought in the same sentence.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Inbox").sheet(isPresented: $ranking) { RankingView() }
    }
    private func remove(_ capture: Capture) { do { try store.deleteCapture(capture) } catch { store.report(error) } }
}

private struct RankingView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
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
                Spacer(minLength: 0)
            }.padding(24).navigationTitle("Rank ideas").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .task { do { try store.prepareRanking() } catch { store.report(error) } }
                .onChange(of: store.ledger.captures) { _, _ in do { try store.prepareRanking() } catch { store.report(error) } }
        }
    }
    private func choice(_ capture: Capture, pair: RankingPair, id: String) -> some View {
        Button {
            do { try store.chooseCapture(capture.id, pair: pair) } catch { store.report(error) }
        } label: {
            Text(capture.text).font(.title3).frame(maxWidth: .infinity, minHeight: 90).padding(12)
        }.buttonStyle(.bordered).accessibilityIdentifier(id)
    }
}
