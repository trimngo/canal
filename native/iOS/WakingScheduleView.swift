import SwiftUI
import LedgerCore

struct WakingScheduleView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var wake = 420
    @State private var bed = 1320
    @State private var selectedDay = Date()
    @State private var dayWake = 420
    @State private var dayBed = 1320
    @State private var status: String?
    private var cal: Calendar { store.ledger.reportingCalendar() }
    var body: some View {
        Form {
            Section {
                timePicker("Wake up", minute: $wake)
                timePicker("Bedtime", minute: $bed)
                Button("Save typical schedule") {
                    var settings = store.ledger.settings; settings.wakeUpMinute = wake; settings.bedtimeMinute = bed
                    do { try store.saveSettings(settings); status = "Typical schedule saved."; loadDay() } catch { store.report(error) }
                }.disabled(wake == bed).accessibilityIdentifier("waking.save")
                Text("\(store.duration(Double((bed - wake + 1440) % 1440))) per typical waking day").font(.footnote)
            } header: { Text("Typical waking hours") } footer: {
                Text("An earlier bedtime clock time means the next morning. Today ends at now or bedtime, whichever comes first. Estimates extend to wake-up and bedtime only on days with logs. Logs outside the waking period stay saved but do not contribute to these estimates.")
            }
            Section {
                DatePicker("Waking date", selection: $selectedDay, displayedComponents: .date).environment(\.timeZone, cal.timeZone)
                    .onChange(of: selectedDay) { _, _ in loadDay() }
                timePicker("Wake up", minute: $dayWake)
                timePicker("Bedtime", minute: $dayBed)
                Button("Save for this date") {
                    do { try store.saveWakingOverride(on: selectedDay, wake: dayWake, bed: dayBed); status = "Date adjustment saved." } catch { store.report(error) }
                }.disabled(dayWake == dayBed)
                Button("Use typical schedule for this date") {
                    do { try store.saveWakingOverride(on: selectedDay, wake: wake, bed: bed, reset: true); loadDay(); status = "Date adjustment removed." } catch { store.report(error) }
                }
            } header: { Text("Adjust one date (optional)") } footer: {
                Text("Overnight periods belong to the date you woke up. If adjacent schedules overlap, the earlier period ends at the next wake-up so time is counted once.")
            }
            Section {
                Text("Reporting time zone: \(cal.timeZone.identifier)")
                if cal.timeZone.identifier != TimeZone.current.identifier {
                    Button("Use current time zone (\(TimeZone.current.identifier))") {
                        var settings = store.ledger.settings; settings.wakingTimeZoneIdentifier = TimeZone.current.identifier
                        do { try store.saveSettings(settings); loadDay() } catch { store.report(error) }
                    }
                }
                Text("The reporting zone stays fixed while traveling unless you change it. Raw log timestamps are never changed. Daylight-saving days use actual elapsed time.").font(.footnote).foregroundStyle(.secondary)
            }
            if let status { Text(status).foregroundStyle(.secondary) }
        }.navigationTitle("Waking schedule").navigationBarTitleDisplayMode(.inline)
            .onAppear { wake = store.ledger.settings.wakeUpMinute ?? 420; bed = store.ledger.settings.bedtimeMinute; selectedDay = store.ledger.wakingDay(containing: Date()); loadDay() }
    }
    private func loadDay() {
        let value = store.ledger.wakingSchedule(on: selectedDay); dayWake = value.wake; dayBed = value.bed
    }
    private func timePicker(_ title: String, minute: Binding<Int>) -> some View {
        DatePicker(title, selection: Binding(get: {
            cal.date(bySettingHour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in minute.wrappedValue = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date) }), displayedComponents: .hourAndMinute)
            .environment(\.timeZone, cal.timeZone)
    }
}
