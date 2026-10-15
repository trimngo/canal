import SwiftUI
import AppIntents
import UniformTypeIdentifiers
import LedgerCore

struct LedgerExport: Transferable {
    var data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: LedgerStore
    @StateObject private var notifications = NotificationScheduler.shared
    @State private var settings = Settings()
    @State private var managingGroups = false
    @State private var testSent = false
    @State private var saving = false
    private let stepMinutes = Array(stride(from: 0, to: 1440, by: 15))
    var body: some View {
        Form {
            Section {
                Toggle("Every 15 minutes", isOn: $settings.notificationsEnabled)
                Picker("Start", selection: $settings.startMinute) {
                    ForEach(stepMinutes, id: \.self) { Text(minuteLabel($0)).tag($0) }
                }
                Picker("Stop", selection: $settings.endMinute) {
                    ForEach(stepMinutes, id: \.self) { Text(minuteLabel($0)).tag($0) }
                }
                Button(saving ? "Saving…" : "Save notification settings") {
                    Task {
                        saving = true; defer { saving = false }
                        do {
                            var proposed = store.ledger.settings
                            proposed.startMinute = settings.startMinute
                            proposed.endMinute = settings.endMinute
                            proposed.notificationsEnabled = settings.notificationsEnabled
                            _ = try proposed.notificationMinutes()
                            if proposed.notificationsEnabled, !(try await notifications.permission()) { throw NotificationError.denied }
                            try await notifications.apply(proposed)
                            try store.saveSettings(proposed)
                            settings = store.ledger.settings
                        } catch {
                            try? await notifications.apply(store.ledger.settings)
                            store.report(error)
                        }
                    }
                }.disabled(saving || !store.storageAvailable)
                Text(notifications.status).font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Check-in notifications") } footer: {
                Text("Default: 7 AM–10 PM. Prompts ask what you’re doing at that moment. A window can span up to 15 hours to stay within system scheduling limits. You can log manually anytime. Alerts follow your Focus and Watch settings.")
            }
            Section("Test delivery") {
                Button("Notify me in 15 seconds") {
                    Task {
                        do { try await notifications.sendTest(); testSent = true } catch { store.report(error) }
                    }
                }
                if testSent { Text("Lock your phone now. Check your phone or Watch in 15 seconds.").font(.footnote) }
            }
            Section("Display") {
                Toggle("Use 24-hour time", isOn: Binding(get: { store.ledger.settings.use24HourTime }, set: { value in
                    var current = store.ledger.settings; current.use24HourTime = value
                    do { try store.saveSettings(current); settings.use24HourTime = value } catch { store.report(error) }
                }))
            }
            Section {
                Picker("Method", selection: Binding(get: { store.ledger.settings.inferenceMethod }, set: { value in
                    var current = store.ledger.settings; current.inferenceMethod = value
                    do { try store.saveSettings(current); settings.inferenceMethod = value } catch { store.report(error) }
                })) {
                    ForEach(InferenceMethod.allCases) { Text($0.name).tag($0) }
                }
            } header: { Text("Estimate time") } footer: {
                Text("Midpoint switches activities halfway between samples. The other method keeps each activity until the next sample. Today covers your first log until now; past days end at the last log. Percentages use tracked time. Changing methods keeps your original samples.")
            }
            Section {
                Button("Manage groups") { managingGroups = true }
            } header: { Text("Activity groups") } footer: {
                Text("Phrase matching and your corrections group activities offline. You can create and rename groups anytime. Existing manual choices stay intact.")
            }
            Section("Your data") {
                Text(store.syncStatus).font(.footnote)
                Button("Sync now") { store.refresh() }
                if let data = try? JSONEncoder().encode(store.ledger) {
                    ShareLink("Export a backup", item: LedgerExport(data: data), preview: SharePreview("Time Ledger backup"))
                }
            }
            Section {
                Text("Say ‘Siri, capture in Ledger,’ then say your task when Siri asks.")
                ShortcutsLink()
            } header: { Text("Siri & Shortcuts") } footer: {
                Text("For a shorter command, create a personal shortcut using Capture a thought and rename it in Apple’s Shortcuts app. Siri controls spoken recognition; this app cannot change a command name in Settings or guarantee free-form task text in a single utterance.")
            }
        }.navigationTitle("Settings")
            .task { settings = store.ledger.settings; await notifications.refreshStatus() }
            .sheet(isPresented: $managingGroups) { GroupManagerView() }
    }
    private func minuteLabel(_ minutes: Int) -> String {
        let start = Calendar.current.startOfDay(for: Date())
        return store.time(Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: start) ?? start)
    }
}
