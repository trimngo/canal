import SwiftUI
import AppIntents
import UniformTypeIdentifiers
import LedgerCore
import Intents

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
    @State private var siriStatus: INSiriAuthorizationStatus = .notDetermined
    private let stepMinutes = Array(stride(from: 0, to: 1440, by: 15))
    var body: some View {
        Form {
            Section {
                NavigationLink("Calendars") { CalendarConnectionView() }.accessibilityIdentifier("settings.calendars")
                NavigationLink("Siri via Reminders") { ReminderInboxSetupView() }
                    .accessibilityIdentifier("settings.reminders")
            } footer: {
                Text("Capture an idea in one sentence: ‘Siri, remind me to…’ Connect a list and set it as your default in iPhone Settings.")
            }
            Section {
                Toggle("Check-in notifications", isOn: $settings.notificationsEnabled)
                    .accessibilityIdentifier("settings.notifications-enabled")
                Picker("Delivery", selection: $settings.notificationDelivery) {
                    ForEach(NotificationDelivery.allCases) { Text($0.name).tag($0) }
                }.accessibilityIdentifier("settings.notification-delivery")
                if settings.notificationDelivery == .watch {
                    Text("Open Dash on your Watch and allow Watch notifications once if prompted. Check-ins are scheduled on the Watch even while you use your iPhone. Focus and Watch notification settings still apply.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Your iPhone schedules check-ins. Apple chooses whether your phone or Watch alerts you. Automatic usually alerts one device, rather than both.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Picker("Timing", selection: $settings.notificationTiming) {
                    ForEach(NotificationTiming.allCases) { Text($0.name).tag($0) }
                }.accessibilityIdentifier("settings.notification-timing")
                Picker(settings.notificationTiming == .regular ? "Interval" : "Average interval", selection: intervalBinding) {
                    ForEach(NotificationTiming.intervals, id: \.self) { Text(intervalLabel($0)).tag($0) }
                }.accessibilityIdentifier("settings.notification-interval")
                Text(timingExplanation).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.notification-explanation")
                Toggle("All day", isOn: $settings.notificationsAllDay).accessibilityIdentifier("settings.notifications-all-day")
                if !settings.notificationsAllDay {
                Picker("Start", selection: $settings.startMinute) {
                    ForEach(stepMinutes, id: \.self) { Text(minuteLabel($0)).tag($0) }
                }
                Picker("Stop", selection: $settings.endMinute) {
                    ForEach(stepMinutes, id: \.self) { Text(minuteLabel($0)).tag($0) }
                }
                }
                Button(saving ? "Saving…" : "Save notification settings") {
                    Task {
                        saving = true; defer { saving = false }
                        do {
                            var proposed = store.ledger.settings
                            proposed.startMinute = settings.startMinute
                            proposed.endMinute = settings.endMinute
                            proposed.notificationsEnabled = settings.notificationsEnabled
                            proposed.notificationsAllDay = settings.notificationsAllDay
                            proposed.notificationTiming = settings.notificationTiming
                            proposed.notificationDelivery = settings.notificationDelivery
                            proposed.regularNotificationInterval = settings.regularNotificationInterval
                            proposed.randomizedNotificationInterval = settings.randomizedNotificationInterval
                            _ = try proposed.notificationMinutes()
                            if proposed.notificationsEnabled, proposed.notificationDelivery == .automatic,
                               !(try await notifications.permission()) { throw NotificationError.denied }
                            try await notifications.apply(proposed, force: true)
                            try store.saveSettings(proposed)
                            settings = store.ledger.settings
                        } catch {
                            try? await notifications.apply(store.ledger.settings, force: true)
                            store.report(error)
                        }
                    }
                }.disabled(saving || !store.storageAvailable).accessibilityIdentifier("settings.save-notifications")
                if settings.notificationDelivery == .automatic {
                    Text(notifications.status).font(.footnote).foregroundStyle(.secondary)
                }
                if !notifications.scheduleStatus.isEmpty {
                    Text(notifications.scheduleStatus).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.notification-schedule-status")
                }
            } header: { Text("Check-in notifications") } footer: {
                Text("Use all day, or a window of up to 15 hours. Use Sleep Focus to silence Dash and mirror Focus on your Watch. Silenced alerts may remain in Notification Center. You can log manually anytime. Your response records what you are doing at that moment.")
            }
            Section("Test delivery") {
                Button("Notify this iPhone in 15 seconds") {
                    Task {
                        do { try await notifications.sendTest(); testSent = true } catch { store.report(error) }
                    }
                }
                if testSent { Text("Lock your phone now. Check your phone or Watch in 15 seconds.").font(.footnote) }
                if settings.notificationDelivery == .watch {
                    Text("For a Watch-only test, open Dash on your Watch → Watch alerts → Test in 15 seconds.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Display") {
                Toggle("Use 24-hour time", isOn: Binding(get: { store.ledger.settings.use24HourTime }, set: { value in
                    var current = store.ledger.settings; current.use24HourTime = value
                    do { try store.saveSettings(current); settings.use24HourTime = value } catch { store.report(error) }
                }))

                Text("Reporting time zone: \(store.ledger.reportingCalendar().timeZone.identifier)").font(.footnote).foregroundStyle(.secondary)
                if store.ledger.reportingCalendar().timeZone.identifier != TimeZone.current.identifier {
                    Button("Use this phone’s time zone") {
                        var current = store.ledger.settings; current.reportingTimeZoneIdentifier = TimeZone.current.identifier
                        do { try store.saveSettings(current) } catch { store.report(error) }
                    }
                }
            }
            Section {
                Picker("Method", selection: Binding(get: { store.ledger.settings.inferenceMethod }, set: { value in
                    var current = store.ledger.settings; current.inferenceMethod = value
                    do { try store.saveSettings(current); settings.inferenceMethod = value } catch { store.report(error) }
                })) {
                    ForEach(InferenceMethod.allCases) { Text($0.name).tag($0) }
                }
            } header: { Text("Estimate time") } footer: {
                Text("Midpoint switches activities halfway between samples. The other method keeps each activity until the next sample. Estimates extend half your notification interval before the first log and after the last. Random mode uses your configured average interval. Estimates are capped at now and calendar-day boundaries; unsampled time outside that period is excluded. Every log counts, regardless of its time. Days without logs are excluded. Changing methods keeps your original samples.")
            }
            Section {
                NavigationLink { DayWindowSettingsView() } label: {
                    LabeledContent("Day window", value: "\(minuteLabel(store.ledger.settings.startMinute))–\(minuteLabel(store.ledger.settings.endMinute))")
                }.accessibilityIdentifier("settings.day-window")
                Button("Categories & targets") { managingGroups = true }
            } header: { Text("Time allocation") } footer: {
                Text("The day window estimates daily goal hours and time remaining. Every log counts, including outside it. Offline category suggestions wait for your confirmation.")
            }
            Section("Your data") {
                Text(store.syncStatus).font(.footnote)
                Text(store.companionStatus).font(.footnote).accessibilityIdentifier("sync.companion.status")
                if let diagnostic = store.companionDiagnostic {
                    Text(diagnostic).font(.caption).foregroundStyle(.secondary)
                }
                Button("Sync now") { store.refresh() }
                if let data = try? JSONEncoder().encode(store.ledger) {
                    ShareLink("Export a backup", item: LedgerExport(data: data), preview: SharePreview("Dash backup"))
                }
            }
            Section {
                Text(store.backupStatus).font(.footnote).accessibilityIdentifier("backup.status")
                Button("Back up now") { store.refresh() }.accessibilityIdentifier("backup.now")
                NavigationLink("Restore a backup") { RestoreBackupView() }.accessibilityIdentifier("backup.restore")
            } header: { Text("Automatic backup") } footer: {
                Text("Your iPhone saves a daily backup in your iCloud Drive after changes, including Watch logs once they sync. Older daily copies are kept. Enable iCloud Drive for Dash in iPhone Settings. An upload-pending backup is still waiting to reach iCloud.")
            }
            Section {
                Text("Direct shortcuts are also available: ‘Siri, capture in Dash’ and ‘Siri, log in Dash.’ Siri may ask for the text. For one-sentence ideas, use Siri via Reminders above.")
                #if targetEnvironment(simulator)
                // Unsigned simulator apps have no Siri entitlement. Calling
                // INPreferences there raises an Objective-C exception.
                Text("Siri capture is available on your iPhone and Watch.").font(.footnote)
                #else
                if siriStatus != .authorized {
                    Button("Enable Siri capture") {
                        INPreferences.requestSiriAuthorization { value in
                            Task { @MainActor in siriStatus = value }
                        }
                    }.accessibilityIdentifier("settings.siri.enable")
                    Text(siriStatus == .denied ? "Siri access is off. Allow Dash in your iPhone’s Siri settings." : "Allow Siri access once to use note capture.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Label("Siri capture enabled", systemImage: "checkmark.circle").font(.footnote)
                }
                #endif
                ShortcutsLink()
            } header: { Text("Siri & Shortcuts") } footer: {
                Text("Siri notes save directly to your inbox with a timestamp. No app confirmation is required. Siri controls recognition and may ask for missing information. The Capture a thought shortcut remains available; personal shortcut names can be changed in Apple’s Shortcuts app.")
            }
        }.navigationTitle("Settings")
            .task {
                settings = store.ledger.settings
                #if !targetEnvironment(simulator)
                siriStatus = INPreferences.siriAuthorizationStatus()
                #endif
                await notifications.refreshStatus()
            }
            .onChange(of: store.ledger.settings) { previous, updated in
                // Follow incoming settings while preserving an unsaved draft.
                var previousDraft = previous; previousDraft.revision = settings.revision
                if settings == previousDraft { settings = updated }
                else {
                    // A window can be edited from its own screen while other
                    // notification fields are still an unsaved local draft.
                    if settings.startMinute == previous.startMinute { settings.startMinute = updated.startMinute }
                    if settings.endMinute == previous.endMinute { settings.endMinute = updated.endMinute }
                }
            }
            .sheet(isPresented: $managingGroups) { GroupManagerView() }
    }
    private var intervalBinding: Binding<Int> {
        Binding(get: {
            settings.notificationTiming == .regular ? settings.regularNotificationInterval : settings.randomizedNotificationInterval
        }, set: { value in
            if settings.notificationTiming == .regular { settings.regularNotificationInterval = value }
            else { settings.randomizedNotificationInterval = value }
        })
    }
    private func intervalLabel(_ minutes: Int) -> String {
        if minutes == 60 { return "1 hour" }
        if minutes == 120 { return "2 hours" }
        return "\(minutes) minutes"
    }
    private var timingExplanation: String {
        if settings.notificationTiming == .randomized {
            let average = Double(settings.randomizedNotificationInterval)
            let lower = (average * 2 / 3).formatted(.number.precision(.fractionLength(0...1)))
            let upper = (average * 4 / 3).formatted(.number.precision(.fractionLength(0...1)))
            let device = settings.notificationDelivery == .watch ? "Watch" : "iPhone"
            return "Random gaps of about \(lower)–\(upper) minutes during your chosen hours. The average is approximate. Up to 60 alerts are queued. Open Dash or save a log on your \(device) to refill them. Background refresh is best effort; alerts pause if the queue runs out."
        }
        if settings.usesQueuedNotifications {
            return "Regular gaps during your chosen hours. This frequent window uses a queue of up to 60 alerts. Open Dash or save a log to refill it; background refresh is best effort."
        }
        return "Check-ins repeat on a regular clock schedule, every \(settings.regularNotificationInterval) minutes. Each timing mode remembers its own interval."
    }
    private func minuteLabel(_ minutes: Int) -> String {
        let start = Calendar.current.startOfDay(for: Date())
        return store.time(Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: start) ?? start)
    }
}
