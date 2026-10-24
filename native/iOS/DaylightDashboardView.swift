import SwiftUI
import HealthKit
import LedgerCore

/// Health data stays in HealthKit and this transient view state. It is never
/// copied to the activity ledger, CloudKit records, exports or backups.
@MainActor
final class DaylightReader: ObservableObject {
    @Published var today: Double?
    @Published var average: Double?
    @Published var representedDays = 0
    @Published var latest: Date?
    @Published var error: String?
    @Published var loading = false
    private let health = HKHealthStore()
    private let type = HKQuantityType(.timeInDaylight)
    func connect(calendar: Calendar) async {
        guard HKHealthStore.isHealthDataAvailable() else { error = "Health data is unavailable on this device."; return }
        do {
            try await health.requestAuthorization(toShare: [], read: [type])
            UserDefaults.standard.set(true, forKey: "daylight.requested")
            await refresh(calendar: calendar)
        } catch { self.error = error.localizedDescription }
    }
    func refresh(calendar: Calendar) async {
        guard !loading, UserDefaults.standard.bool(forKey: "daylight.requested"), HKHealthStore.isHealthDataAvailable() else { return }
        loading = true; defer { loading = false }
        do {
            let now = Date(), day = calendar.startOfDay(for: now)
            var past: [Double] = []
            for offset in -7 ... 0 {
                let start = calendar.date(byAdding: .day, value: offset, to: day)!
                let end = min(now, calendar.date(byAdding: .day, value: 1, to: start)!)
                let value = try await minutes(from: start, to: end)
                if offset == 0 { today = value } else if let value { past.append(value) }
            }
            representedDays = past.count
            average = past.isEmpty ? nil : past.reduce(0, +) / Double(past.count)
            latest = try await latestRecord(before: now)
            error = nil
        } catch { self.error = "Daylight data could not be read. Try again later." }
    }
    private func minutes(from start: Date, to end: Date) async throws -> Double? {
        guard end > start else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: .minute())) }
            }
            health.execute(query)
        }
    }
    private func latestRecord(before now: Date) async throws -> Date? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: nil, end: now), limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first?.endDate) }
            }
            health.execute(query)
        }
    }
}

struct DaylightDashboardView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var reader = DaylightReader()
    @State private var details = false
    @AppStorage("daylight.requested") private var requested = false
    var body: some View {
        HStack {
            Image(systemName: "sun.max").foregroundStyle(.orange)
            if requested {
                Button { details = true } label: {
                    Text("Daylight · " + (reader.today.map { store.duration($0) + " recorded today" } ?? "No data today"))
                        .font(.caption).foregroundStyle(.secondary)
                }.accessibilityIdentifier("dashboard.daylight")
            } else {
                Button("Connect daylight") { Task { await reader.connect(calendar: store.ledger.reportingCalendar()) } }
                    .font(.caption).accessibilityIdentifier("dashboard.daylight.connect")
            }
            if reader.loading { ProgressView().controlSize(.mini) }
        }
        .task { await reader.refresh(calendar: store.ledger.reportingCalendar()) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reader.refresh(calendar: store.ledger.reportingCalendar()) } } }
        .sheet(isPresented: $details) {
            NavigationStack {
                List {
                    LabeledContent("Recorded today", value: reader.today.map { store.duration($0) } ?? "No data")
                    LabeledContent("Previous 7 days average", value: reader.average.map { store.duration($0) + "/day" } ?? "No data")
                    Text("\(reader.representedDays) of 7 completed days recorded").font(.caption).foregroundStyle(.secondary)
                    if let latest = reader.latest { LabeledContent("Latest record", value: latest.formatted(date: .abbreviated, time: .shortened)) }
                    Text("Apple Watch records estimated time outdoors in daylight. Records may arrive later; this is not a live timer. Daylight can overlap your activities and does not add to logged time.").font(.footnote).foregroundStyle(.secondary)
                    Text("No data can mean that no records are available or Health access is off. You can manage access in the Health app.").font(.footnote).foregroundStyle(.secondary)
                    if let error = reader.error { Text(error).foregroundStyle(.secondary) }
                    Button("Refresh") { Task { await reader.refresh(calendar: store.ledger.reportingCalendar()) } }
                    Button("Health access") { Task { await reader.connect(calendar: store.ledger.reportingCalendar()) } }
                }.navigationTitle("Time in daylight").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { details = false } } }
            }.presentationDetents([.medium, .large])
        }
        .alert("Daylight", isPresented: Binding(get: { reader.error != nil && !requested }, set: { if !$0 { reader.error = nil } })) {
            Button("OK") { reader.error = nil }
        } message: { Text(reader.error ?? "") }
    }
}
