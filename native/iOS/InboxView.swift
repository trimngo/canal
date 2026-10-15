import SwiftUI
import LedgerCore

struct InboxView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var text = ""
    @State private var showDone = false
    var captures: [Capture] { store.ledger.captures.filter { $0.isDone == showDone }.sorted { $0.createdAt > $1.createdAt } }
    var body: some View {
        List {
            Section {
                TextField("Get it out of your head…", text: $text, axis: .vertical).lineLimit(2...5)
                    .accessibilityIdentifier("inbox.text")
                Button("Capture") {
                    do { try store.addCapture(text); text = "" } catch { store.report(error) }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                    .accessibilityIdentifier("inbox.save")
            } footer: { Text("Thoughts and tasks stay here until you review them. Captures don’t count toward time spent.") }
            Section {
                Toggle("Show completed", isOn: $showDone)
                if captures.isEmpty { Text(showDone ? "No completed captures." : "Your inbox is clear.").foregroundStyle(.secondary) }
                ForEach(captures) { capture in
                    HStack(alignment: .top, spacing: 14) {
                        Button {
                            do { try store.setCaptureDone(capture, done: !capture.isDone) } catch { store.report(error) }
                        } label: { Image(systemName: capture.isDone ? "checkmark.circle.fill" : "circle").font(.title3) }
                            .buttonStyle(.borderless).accessibilityLabel(capture.isDone ? "Reopen capture" : "Complete capture")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(capture.text)
                            Text("\(capture.createdAt.formatted(date: .abbreviated, time: .omitted)) · \(store.time(capture.createdAt))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
            }
            Section("Hands-free capture") {
                Text("Try: ‘Siri, create a note in Ledger called try shorter lessons.’ Say the whole thought in the same sentence.")
                Text("Timed task reminders will come later. This first inbox is for capturing and reviewing.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Inbox")
    }
}
