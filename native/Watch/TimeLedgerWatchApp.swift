import SwiftUI
import WatchKit
import LedgerCore

@main
struct TimeLedgerWatchApp: App {
    @StateObject private var store = LedgerStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            WatchHomeView().environmentObject(store).tint(.mint)
                .task {
                    store.start(); LedgerShortcuts.updateAppShortcutParameters()
                    NotificationScheduler.shared.configureActions()
                }
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.refresh() } }
                .alert("Couldn’t save", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
        WKNotificationScene(controller: CheckInNotificationController.self, category: "CHECKIN")
    }
}
