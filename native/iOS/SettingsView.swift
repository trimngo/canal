import SwiftUI
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
    @State private var categoryName = ""
    @State private var editingCategory: LedgerCategory?
    @State private var testSent = false
    @State private var saving = false
    private let stepMinutes = Array(stride(from: 0, to: 1440, by: 15))
    var body: some View {
        Form {
            Section("Check-in notifications") {
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
                            _ = try settings.notificationMinutes()
                            if settings.notificationsEnabled, !(try await notifications.permission()) { throw NotificationError.denied }
                            try await notifications.apply(settings)
                            try store.saveSettings(settings)
                        } catch {
                            try? await notifications.apply(store.ledger.settings)
                            store.report(error)
                        }
                    }
                }.disabled(saving || !store.storageAvailable)
                Text(notifications.status).font(.footnote).foregroundStyle(.secondary)
            } footer: {
                Text("Default: 7:15 AM–10 PM. Prompts cover the preceding 15 minutes. A window can span up to 15 hours to stay within system scheduling limits. Alerts follow your Focus and Watch settings.")
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
            Section("Categories") {
                ForEach(store.ledger.categories) { category in
                    Button(category.name) { editingCategory = category; categoryName = category.name }
                }
                Button("Add category") { editingCategory = LedgerCategory(id: "", name: ""); categoryName = "" }
            } footer: { Text("Renaming a category updates its label everywhere. Google Calendar is not connected.") }
            Section("Your data") {
                Text(store.syncStatus).font(.footnote)
                Button("Sync now") { store.refresh() }
                if let data = try? JSONEncoder().encode(store.ledger) {
                    ShareLink("Export a backup", item: LedgerExport(data: data), preview: SharePreview("Time Ledger backup"))
                }
            }
        }.navigationTitle("Settings")
            .task { settings = store.ledger.settings; await notifications.refreshStatus() }
            .alert(editingLedgerCategory?.id == "" ? "New category" : "Rename category", isPresented: Binding(get: { editingCategory != nil }, set: { if !$0 { editingCategory = nil } })) {
                TextField("Category name", text: $categoryName)
                Button("Save") {
                    do { try store.saveLedgerCategory(id: editingLedgerCategory?.id == "" ? nil : editingLedgerCategory?.id, name: categoryName) } catch { store.report(error) }
                    editingCategory = nil
                }
                Button("Cancel", role: .cancel) { editingCategory = nil }
            }
    }
    private func minuteLabel(_ minutes: Int) -> String {
        let start = Calendar.current.startOfDay(for: Date())
        return store.time(Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: start) ?? start)
    }
}
