import SwiftUI
import LedgerCore

/// Uses the existing shared start/end settings; no new schedule or log filter.
struct DayWindowSettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var start = 7 * 60
    @State private var end = 22 * 60
    @State private var saving = false
    @State private var error: String?
    private let minutes = Array(stride(from: 0, to: 1440, by: 15))

    var body: some View {
        Form {
            Section {
                Picker("Start", selection: $start) {
                    ForEach(minutes, id: \.self) { Text(label($0)).tag($0) }
                }.accessibilityIdentifier("goals.window-start")
                Picker("End", selection: $end) {
                    ForEach(minutes, id: \.self) { Text(label($0)).tag($0) }
                }.accessibilityIdentifier("goals.window-end")
            } footer: {
                Text("This window estimates daily goal hours and time left. All log entries still count, including outside it. Choose a same-day window up to 15 hours.")
            }
            Section {
                Text(store.ledger.settings.notificationsAllDay
                     ? "Check-ins currently run all day. Changing this window keeps that choice."
                     : "Check-ins use these same hours. Changing this window updates their schedule on your phone and Watch.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Time zone: \(store.ledger.reportingCalendar().timeZone.identifier)").font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("goals.window-error") }
        }.navigationTitle("Day window").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Done") { save() }
                        .disabled(saving || !store.storageAvailable).accessibilityIdentifier("goals.window-save")
                }
            }
            .onAppear { start = store.ledger.settings.startMinute; end = store.ledger.settings.endMinute }
    }

    private func label(_ minute: Int) -> String {
        let calendar = store.ledger.reportingCalendar()
        let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        return store.time(date)
    }

    private func save() {
        Task { @MainActor in
            saving = true; defer { saving = false }
            do {
                var proposed = store.ledger.settings
                proposed.startMinute = start; proposed.endMinute = end
                var validation = proposed; validation.notificationsAllDay = false
                try validation.validateNotificationSettings()
                try store.saveSettings(proposed)
                // Saving the estimate is independent of notification permission.
                // Existing observers also apply it on the paired device.
                do { try await NotificationScheduler.shared.apply(proposed, force: true) }
                catch { store.report(error) }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
