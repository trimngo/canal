import SwiftUI
import LedgerCore

@main
struct TimeLedgerApp: App {
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

struct RootView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var path: [LedgerScreen] = []
    var body: some View {
        NavigationStack(path: $path) {
            DayView().navigationDestination(for: LedgerScreen.self) { screen in
                switch screen {
                case .calendar: CalendarHistoryView()
                case .inbox: InboxView()
                case .settings: SettingsView()
                }
            }
        }
        .onChange(of: store.sampleRequestID) { _, _ in path.removeAll() }
    }
}
