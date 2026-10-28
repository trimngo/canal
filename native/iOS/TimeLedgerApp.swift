import SwiftUI
import LedgerCore
import Intents

@main
struct TimeLedgerApp: App {
    @UIApplicationDelegateAdaptor(SiriAppDelegate.self) private var siriDelegate
    @StateObject private var store = LedgerStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(Color(red: 0.13, green: 0.43, blue: 0.38))
                #if DEBUG
                .overlay(alignment: .top) {
                    if ProcessInfo.processInfo.arguments.contains("--ui-watch-restart-repro") {
                        WatchRestartReproductionView().environmentObject(store)
                    }
                }
                #endif
                .task {
                    store.start(); LedgerShortcuts.updateAppShortcutParameters()
                    do { try await NotificationScheduler.shared.apply(store.ledger.settings, force: true) } catch { store.report(error) }
                    await ReminderInbox.shared.refresh()
                    await CalendarImport.shared.refresh()
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-notification-checkin") {
                        NotificationScheduler.shared.presentSample()
                    }
                    if ProcessInfo.processInfo.arguments.contains("--ui-quick-reply") {
                        do { try store.saveQuickSample("Direct notification reply UI fixture", id: "ui-notification-reply") }
                        catch { store.report(error) }
                    }
                    if ProcessInfo.processInfo.arguments.contains("--ui-siri-capture") {
                        let intent = INCreateNoteIntent(title: INSpeakableString(spokenPhrase: "One sentence Siri UI fixture"), content: nil, groupName: nil)
                        if let handler = siriDelegate.application(UIApplication.shared, handlerFor: intent) as? SiriCaptureHandler {
                            handler.handle(intent: intent) { _ in }
                        }
                    }
                    if ProcessInfo.processInfo.arguments.contains("--ui-siri-routes") {
                        for text in ["idea, Bicycle idea UI fixture", "doing, Bicycle activity UI fixture"] {
                            let intent = INCreateNoteIntent(title: INSpeakableString(spokenPhrase: text), content: nil, groupName: nil)
                            if let handler = siriDelegate.application(UIApplication.shared, handlerFor: intent) as? SiriCaptureHandler {
                                handler.handle(intent: intent) { _ in }
                            }
                        }
                    }
                    if ProcessInfo.processInfo.arguments.contains("--ui-siri-timers") {
                        do {
                            for text in ["Eat food", "Cook food for ten minutes"] {
                                if let task = try await SpokenTimerTaskQuery().entities(matching: text).first {
                                    var intent = QueueSpokenTimerIntent(); intent.task = task
                                    _ = try await intent.perform()
                                }
                            }
                        } catch { store.report(error) }
                    }
                    if ProcessInfo.processInfo.arguments.contains("--ui-live-timer-restart"), let token = store.ledger.timerControl?.token {
                        do { _ = try await RestartTimerIntent(token: token).perform() }
                        catch { store.report(error) }
                    }
                    if ProcessInfo.processInfo.arguments.contains("--ui-system-alarm-silence"), let token = store.ledger.timerControl?.token {
                        await NotificationScheduler.shared.applyTimer(store.ledger, writer: store.writer)
                        _ = try? await SilenceTimerAlarmIntent(token: token).perform()
                    }
                    if ProcessInfo.processInfo.arguments.contains("--ui-system-alarm-expired"), let token = store.ledger.timerControl?.token {
                        do {
                            try store.expireSystemAlarmForUITest()
                            _ = try await SilenceTimerAlarmIntent(token: token).perform()
                            _ = try await SilenceTimerAlarmIntent(token: token).perform()
                        } catch { store.report(error) }
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refresh()
                        Task {
                            await ReminderInbox.shared.refresh()
                            await CalendarImport.shared.refresh()
                            do { try await NotificationScheduler.shared.apply(store.ledger.settings, force: true) } catch { store.report(error) }
                        }
                    }
                    if phase == .background { ReminderInbox.shared.scheduleBackgroundRefresh(); CalendarImport.shared.scheduleBackgroundRefresh() }
                }
                .onChange(of: store.ledger.settings) { _, settings in
                    Task { do { try await NotificationScheduler.shared.apply(settings) } catch { store.report(error) } }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Task { do { try await NotificationScheduler.shared.apply(store.ledger.settings, force: true) } catch { store.report(error) } }
                }
                .alert("Couldn’t complete that", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}

enum LedgerScreen: Hashable { case calendar, targets, inbox, settings }
private enum AppTab: Hashable { case today, commitments, timers, inbox, settings }

struct RootView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var path: [LedgerScreen] = []
    @State private var tab: AppTab = .today
    @State private var capturing = false
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $path) {
                DayView().navigationDestination(for: LedgerScreen.self) { destination($0) }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink(destination: CheckInView()) { Label("Log", systemImage: "plus.circle") }.accessibilityIdentifier("today.log")
                        }
                    }
            }.tabItem { Label("Today", systemImage: "chart.pie") }.tag(AppTab.today)
            NavigationStack {
                CommitmentsView().navigationDestination(for: LedgerScreen.self) { destination($0) }
            }.tabItem { Label("Commitments", systemImage: "checkmark.circle") }.tag(AppTab.commitments)
            NavigationStack { TimerQueueView() }.tabItem { Label("Timers", systemImage: "timer") }.tag(AppTab.timers)
            NavigationStack { InboxView() }.tabItem { Label("Inbox", systemImage: "tray") }.tag(AppTab.inbox)
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(AppTab.settings)
        }
        .safeAreaInset(edge: .top, spacing: 0) { LogDeletionUndoBar() }
        .onChange(of: tab) { _, _ in UIApplication.shared.dismissLedgerKeyboard() }
        .onAppear {
            showRequestedCapture()
            if store.showingTimerQueue { tab = .timers }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-timer-fixture") || ProcessInfo.processInfo.arguments.contains("--ui-timer-open") { store.openTimers() }
            #endif
        }
        .onChange(of: store.sampleRequestID) { _, _ in showRequestedCapture() }
        .onChange(of: store.timerRequestID) { _, _ in tab = .timers }
        .fullScreenCover(isPresented: $capturing) { QuickLogCaptureView().id(store.sampleRequestID) }
        .onOpenURL { url in if TimerQueueShortcut.matches(url) { store.openTimers() } }
    }
    @ViewBuilder private func destination(_ screen: LedgerScreen) -> some View {
        switch screen {
        case .calendar: CalendarHistoryView()
        case .targets: TargetsView()
        case .inbox: InboxView()
        case .settings: SettingsView()
        }
    }
    private func showRequestedCapture() {
        guard store.pendingLogRequest else { return }
        store.showingTimerQueue = false
        tab = .today; path.removeAll(); capturing = true; store.pendingLogRequest = false
    }
}
