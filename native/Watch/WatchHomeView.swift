import SwiftUI
import LedgerCore

struct WatchHomeView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var activity = ""
    @State private var categoryIDs: [String] = []
    @State private var capture = ""
    @State private var saved = false
    @State private var tab = 2
    @State private var notificationSettings = false
    var body: some View {
        TabView(selection: $tab) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What are you doing now?").font(.headline)
                    Text("Record a moment in your day.").font(.caption).foregroundStyle(.secondary)
                    TextField("Dictate an answer", text: $activity)
                    if let suggestion = store.ledger.suggestedCategory(for: activity) {
                        Text("Suggested: \(store.categoryName(suggestion))").font(.caption)
                        if categoryIDs != [suggestion] {
                            Button(categoryIDs.isEmpty ? "Use \(store.categoryName(suggestion))" : "Use only \(store.categoryName(suggestion))") { categoryIDs = [suggestion] }
                        } else {
                            Text("Confirmed").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    CategorySelectionPicker(selection: $categoryIDs)
                    Button(saved ? "Saved ✓" : "Save sample") {
                        do {
                            try store.saveSample(activity: activity, categoryIDs: categoryIDs)
                            activity = ""; categoryIDs = []; saved = true
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
                        Button("Add timer", systemImage: "mic.fill") { store.openTimers(dictate: true) }
                            .accessibilityIdentifier("watch.timer-add")
                        Button("Timer queue", systemImage: "timer") { tab = 3 }
                            .accessibilityIdentifier("watch.timers")
                        Button("Watch alerts") { notificationSettings = true }
                            .accessibilityIdentifier("watch.notifications")
                        ForEach(store.ledger.history(range: .today, now: now).rows) { row in
                            VStack(alignment: .leading) {
                                Text(row.name)
                                Text("\(row.percent, specifier: "%.0f")% · \(store.duration(row.minutes))").foregroundStyle(.secondary)
                            }.font(.caption)
                        }
                        Text("Since today’s first log · through now").font(.caption2).foregroundStyle(.secondary)
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("--ui-watch-inspect-ledger") {
                            Text("\(store.ledger.entries.count)").accessibilityIdentifier("watch.debug.sample-count")
                            Text(store.ledger.entries.last?.activity ?? "No logs").accessibilityIdentifier("watch.debug.last-sample")
                        }
                        #endif
                        Button("Sync") { store.refresh() }
                        Text(store.companionStatus).font(.caption2).foregroundStyle(.secondary)
                        if let diagnostic = store.companionDiagnostic {
                            Text(diagnostic).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }.tag(2)
            NavigationStack { TimerQueueView() }.tag(3)
        }.tabViewStyle(.verticalPage)
            .onAppear { if store.showingTimerQueue { tab = 3 } }
            .onChange(of: store.timerRequestID) { _, _ in tab = 3 }
            .sheet(isPresented: $notificationSettings) { WatchNotificationSettingsView() }
            .onChange(of: activity) { old, value in
                if !value.isEmpty { saved = false }
                if OfflineGrouping.normalized(old) != OfflineGrouping.normalized(value) { categoryIDs = [] }
            }
            .onChange(of: store.sampleRequestID) { _, _ in
                tab = 0; activity = store.quickReplyDraft ?? ""; store.quickReplyDraft = nil
                categoryIDs = []; saved = false
            }
    }
}
