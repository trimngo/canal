import SwiftUI
import LedgerCore

struct WatchNotificationSettingsView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notifications = NotificationScheduler.shared
    @State private var saving = false
    @State private var testSent = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Get check-ins on this Watch, including while you use your iPhone.").font(.caption)
                    Button("Enable Watch alerts") {
                        Task {
                            saving = true; defer { saving = false }
                            do {
                                guard try await notifications.permission() else { throw NotificationError.denied }
                                var settings = store.ledger.settings
                                settings.notificationsEnabled = true; settings.notificationDelivery = .watch
                                try await notifications.apply(settings, force: true)
                                try store.saveSettings(settings)
                            } catch {
                                try? await notifications.apply(store.ledger.settings, force: true)
                                store.report(error)
                            }
                        }
                    }.buttonStyle(.borderedProminent).disabled(saving || !store.storageAvailable)
                        .accessibilityIdentifier("watch.notifications.enable")
                    Text(notifications.status).font(.caption2).foregroundStyle(.secondary)
                    Text(notifications.scheduleStatus).font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("watch.notifications.status")
                    Button("Test in 15 seconds") {
                        Task { do { try await notifications.sendTest(); testSent = true } catch { store.report(error) } }
                    }.accessibilityIdentifier("watch.notifications.test")
                    if testSent { Text("Test sent. Lower your wrist and check this Watch in 15 seconds.").font(.caption2) }
                    if store.ledger.settings.notificationsEnabled, store.ledger.settings.notificationDelivery == .watch {
                        Button("Turn off check-ins") {
                            var settings = store.ledger.settings; settings.notificationsEnabled = false
                            do { try store.saveSettings(settings) } catch { store.report(error) }
                        }.accessibilityIdentifier("watch.notifications.off")
                    }
                    Text("Choose timing and interval in Dash Settings on iPhone. In Watch mode, this Watch owns the schedule. Focus, Theater Mode, and notification settings can still silence alerts. Random schedules refill when Dash runs or you log here; background refresh is best effort.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.navigationTitle("Watch alerts")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .task { do { try await notifications.apply(store.ledger.settings, force: true) } catch { store.report(error) } }
        }
    }
}
