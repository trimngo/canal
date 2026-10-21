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
                    Text("Delivery: \(store.ledger.settings.notificationDelivery.name)").font(.caption.bold())
                        .accessibilityIdentifier("watch.notifications.delivery-mode")
                    Text(store.ledger.settings.notificationsEnabled ? "Check-ins: On" : "Check-ins: Off")
                        .font(.caption).accessibilityIdentifier("watch.notifications.enabled-status")
                    Text(store.ledger.settings.notificationDelivery == .automatic
                         ? "Your iPhone schedules check-ins. Apple chooses whether the phone or Watch alerts you. No separate Watch schedule is needed."
                         : "This Watch schedules check-ins, including while you use your iPhone.").font(.caption)
                    if store.ledger.settings.notificationDelivery == .watch, !notifications.permissionGranted {
                        Button("Allow Watch notifications") {
                            Task {
                                saving = true; defer { saving = false }
                                do {
                                    guard try await notifications.permission() else { throw NotificationError.denied }
                                    try await notifications.apply(store.ledger.settings, force: true)
                                } catch {
                                    try? await notifications.apply(store.ledger.settings, force: true)
                                    store.report(error)
                                }
                            }
                        }.buttonStyle(.borderedProminent).disabled(saving || !store.storageAvailable)
                            .accessibilityIdentifier("watch.notifications.enable")
                    }
                    if store.ledger.settings.notificationDelivery == .watch || testSent {
                        Text(notifications.status).font(.caption2).foregroundStyle(.secondary)
                    }
                    if store.ledger.settings.notificationDelivery == .watch || !store.ledger.settings.notificationsEnabled {
                        Text(notifications.scheduleStatus).font(.caption2).foregroundStyle(.secondary)
                            .accessibilityIdentifier("watch.notifications.status")
                    }
                    Button("Test this Watch in 15 seconds") {
                        Task { do { try await notifications.sendTest(); testSent = true } catch { store.report(error) } }
                    }.accessibilityIdentifier("watch.notifications.test")
                    if testSent { Text("Test sent. Lower your wrist and check this Watch in 15 seconds.").font(.caption2) }
                    Text("This test checks this Watch only. It does not change delivery mode.").font(.caption2).foregroundStyle(.secondary)
                    if store.ledger.settings.notificationsEnabled, store.ledger.settings.notificationDelivery == .watch {
                        Button("Turn off all check-ins") {
                            var settings = store.ledger.settings; settings.notificationsEnabled = false
                            do { try store.saveSettings(settings) } catch { store.report(error) }
                        }.accessibilityIdentifier("watch.notifications.off")
                    }
                    Text("Delivery, timing, and check-ins on/off are shared settings. Change them in Dash Settings on iPhone and tap Save notification settings. Focus, Theater Mode, and notification settings can still silence alerts. Random schedules refill when Dash runs or you log here; background refresh is best effort.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.navigationTitle("Watch alerts")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .task { store.refresh(); do { try await notifications.apply(store.ledger.settings, force: true) } catch { store.report(error) } }
        }
    }
}
