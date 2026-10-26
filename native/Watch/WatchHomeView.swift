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
    @State private var timerOptions = false
    @State private var showingTimerRows = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationStack {
        Group {
            if store.showingTimerQueue {
                ZStack {
                if showingTimerRows {
                    TimerQueueView(watchShowsQueue: true, showCurrentTimer: { showingTimerRows = false })
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                } else {
                    TimerQueueView(showTimerQueue: { showingTimerRows = true })
                        .transition(reduceMotion ? .opacity : .move(edge: .top))
                }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.3), value: showingTimerRows)
            } else { homePages }
        }
            .onAppear {
                if store.ledger.currentTimer != nil { store.showingTimerQueue = true; showingTimerRows = false }
            }
            .onChange(of: store.timerRequestID) { _, _ in showingTimerRows = false }
            .onChange(of: store.ledger.timerControl?.token) { _, _ in
                if store.ledger.currentTimer != nil, store.ledger.timerControl?.dueAt != nil {
                    store.showingTimerQueue = true; showingTimerRows = false
                }
            }
            .sheet(isPresented: $notificationSettings) { WatchNotificationSettingsView() }
            .sheet(isPresented: $timerOptions) {
                NavigationStack {
                    List {
                        NavigationLink(destination: TimerSettingsView()) {
                            Label("Haptics & timer settings", systemImage: "waveform")
                        }.accessibilityIdentifier("timers.alarm-settings")
                        if let control = store.ledger.timerControl, store.ledger.currentTimer != nil, control.owner != store.writer {
                            Button("Use Watch for alerts") {
                                do { try store.changeTimer("here") } catch { store.report(error) }
                            }
                        }
                        Button("Watch Home") { timerOptions = false; store.showingTimerQueue = false }
                    }.navigationTitle("Timer options")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { timerOptions = false } } }
                }
            }
            .onChange(of: activity) { old, value in
                if !value.isEmpty { saved = false }
                if OfflineGrouping.normalized(old) != OfflineGrouping.normalized(value) { categoryIDs = [] }
            }
            .onChange(of: store.sampleRequestID) { _, _ in
                store.showingTimerQueue = false
                tab = 0; activity = store.quickReplyDraft ?? ""; store.quickReplyDraft = nil
                categoryIDs = []; saved = false
            }
            .toolbar {
                if store.showingTimerQueue, !showingTimerRows {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { timerOptions = true } label: { Image(systemName: "ellipsis").foregroundStyle(.black) }
                            .accessibilityLabel("Timer options").accessibilityIdentifier("timers.options")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { store.openTimers(dictate: true) } label: { Image(systemName: "plus").font(.title3.bold()).foregroundStyle(.black) }
                            .accessibilityLabel("Add timer").accessibilityIdentifier("timers.dictate").disabled(!store.storageAvailable)
                    }
                }
            }
        }
    }
    private var homePages: some View {
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
                        Button("Timer queue", systemImage: "timer") { store.openTimers() }
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
        }.tabViewStyle(.verticalPage)
    }

}
