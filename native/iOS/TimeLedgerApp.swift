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
                .task {
                    store.start(); LedgerShortcuts.updateAppShortcutParameters()
                    do { try await NotificationScheduler.shared.apply(store.ledger.settings) } catch { store.report(error) }
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
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refresh()
                        Task { do { try await NotificationScheduler.shared.apply(store.ledger.settings) } catch { store.report(error) } }
                    }
                }
                .onChange(of: store.ledger.settings) { _, settings in
                    Task { do { try await NotificationScheduler.shared.apply(settings) } catch { store.report(error) } }
                }
                .alert("Couldn’t complete that", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}

enum LedgerScreen: Hashable { case calendar, inbox, settings }
private enum AppTab: Hashable { case today, log, inbox, settings }

struct RootView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [LedgerScreen] = []
    @State private var tab: AppTab = .today
    @State private var capturing = false
    @State private var wasBackgrounded = false
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $path) {
                DayView().navigationDestination(for: LedgerScreen.self) { screen in
                    switch screen {
                    case .calendar: CalendarHistoryView()
                    case .inbox: InboxView()
                    case .settings: SettingsView()
                    }
                }
            }.tabItem { Label("Today", systemImage: "chart.pie") }.tag(AppTab.today)
            NavigationStack { CheckInView() }.tabItem { Label("Log", systemImage: "plus.circle") }.tag(AppTab.log)
            NavigationStack { InboxView() }.tabItem { Label("Inbox", systemImage: "tray") }.tag(AppTab.inbox)
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(AppTab.settings)
        }
        .onAppear { showRequestedCapture() }
        .onChange(of: store.sampleRequestID) { _, _ in showRequestedCapture() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { wasBackgrounded = true }
            if phase == .active, wasBackgrounded {
                wasBackgrounded = false
                if !capturing { tab = .today; path.removeAll() }
            }
        }
        .fullScreenCover(isPresented: $capturing) { QuickLogCaptureView().id(store.sampleRequestID) }
    }
    private func showRequestedCapture() {
        guard store.pendingLogRequest else { return }
        tab = .today; path.removeAll(); capturing = true; store.pendingLogRequest = false
    }
}
