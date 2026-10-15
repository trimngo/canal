import SwiftUI
import LedgerCore

struct WatchHomeView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var activity = ""
    @State private var categoryID = ""
    @State private var capture = ""
    @State private var saved = false
    @State private var tab = 2
    var body: some View {
        TabView(selection: $tab) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What are you doing now?").font(.headline)
                    Text("Record a moment in your day.").font(.caption).foregroundStyle(.secondary)
                    TextField("Dictate an answer", text: $activity)
                    if let suggestion = store.ledger.suggestedCategory(for: activity) {
                        Text("Suggested: \(store.categoryName(suggestion))").font(.caption)
                        if categoryID != suggestion {
                            Button("Use \(store.categoryName(suggestion))") { categoryID = suggestion }
                        } else {
                            Text("Confirmed").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Picker("Group", selection: $categoryID) {
                        Text("Uncategorized").tag("")
                        ForEach(store.ledger.categories) { Text($0.name).tag($0.id) }
                    }
                    Button(saved ? "Saved ✓" : "Save sample") {
                        do {
                            try store.saveSample(activity: activity, categoryID: categoryID.isEmpty ? nil : categoryID)
                            activity = ""; categoryID = ""; saved = true
                        } catch { store.report(error) }
                    }.buttonStyle(.borderedProminent).disabled(activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                    Button("New sample") { store.beginSample() }.font(.caption)
                }.padding(.horizontal, 4)
            }.tag(0)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Get it out of your head.").font(.headline)
                    TextField("Capture a thought", text: $capture)
                    Button("Save to inbox") {
                        do { try store.addCapture(capture); capture = "" } catch { store.report(error) }
                    }.buttonStyle(.borderedProminent).disabled(capture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                    Text("You can review it on your phone.").font(.caption).foregroundStyle(.secondary)
                }
            }.tag(1)
            TimelineView(.periodic(from: Date(), by: 60)) { _ in
                let now = Date()
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Estimated today").font(.headline)
                        Button("Log now") { store.beginSample() }
                        ForEach(store.ledger.breakdown(on: now, now: now).filter { $0.minutes > 0 }.sorted { $0.minutes > $1.minutes }) { row in
                            VStack(alignment: .leading) {
                                Text(row.name)
                                Text("\(row.percent, specifier: "%.0f")% · \(store.duration(row.minutes))").foregroundStyle(.secondary)
                            }.font(.caption)
                        }
                        Text("Of time since your first log").font(.caption2).foregroundStyle(.secondary)
                        Button("Sync") { store.refresh() }
                    }
                }
            }.tag(2)
        }.tabViewStyle(.verticalPage)
            .onChange(of: activity) { old, value in
                if !value.isEmpty { saved = false }
                if OfflineGrouping.normalized(old) != OfflineGrouping.normalized(value) { categoryID = "" }
            }
            .onChange(of: store.sampleRequestID) { _, _ in
                tab = 0; activity = store.quickReplyDraft ?? ""; store.quickReplyDraft = nil
                categoryID = ""; saved = false
            }
    }
}
