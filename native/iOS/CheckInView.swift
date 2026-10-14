import SwiftUI
import LedgerCore

struct CheckInView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var saved = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("One moment at a time.").font(.subheadline).foregroundStyle(.secondary)
                Text("What are you doing right now?").font(.largeTitle.bold())
                CheckInEditor { saved = true }.id(store.sampleRequestID)
                if saved {
                    Label("Saved. You can change it anytime.", systemImage: "checkmark.circle.fill").foregroundStyle(.tint)
                    Button("Log another moment") { store.beginSample() }
                }
                Text("Log whenever you want. Each sample records one moment; your day’s time is estimated from those samples.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }.scrollDismissesKeyboard(.interactively)
            .navigationTitle("Check in").navigationBarTitleDisplayMode(.inline)
            .disabled(!store.storageAvailable)
            .onChange(of: store.sampleRequestID) { _, _ in saved = false }
    }
}

struct CheckInEditor: View {
    @EnvironmentObject var store: LedgerStore
    var entry: CheckIn? = nil
    var onSave: () -> Void = {}
    @State private var activity = ""
    @State private var categoryID = ""
    @State private var recordNow = true
    @State private var timestamp = Date()
    @State private var saving = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TextField("Preparing classes, walking, resting…", text: $activity, axis: .vertical)
                .lineLimit(3...6).padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                .focused($focused).accessibilityIdentifier("checkin.activity")
            Picker("Category", selection: $categoryID) {
                Text("Categorize later").tag("")
                ForEach(store.ledger.categories) { Text($0.name).tag($0.id) }
            }.pickerStyle(.menu).accessibilityIdentifier("checkin.category")
            Toggle("Use current time", isOn: $recordNow)
                .onChange(of: recordNow) { _, value in if !value, entry == nil { timestamp = Date() } }
            if !recordNow {
                DatePicker("Sample time", selection: $timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            }
            Button {
                guard !saving else { return }
                saving = true
                focused = false
                do {
                    try store.saveSample(id: entry?.id, at: recordNow ? Date() : timestamp,
                                         activity: activity, categoryID: categoryID.isEmpty ? nil : categoryID)
                    if entry == nil { activity = "" }
                    onSave()
                } catch { store.report(error) }
                saving = false
            } label: { Text(saving ? "Saving…" : "Save sample").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10) }
                .buttonStyle(.borderedProminent)
                .disabled(saving || activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                .accessibilityIdentifier("checkin.save")
        }.onAppear {
            if let entry {
                activity = entry.activity; categoryID = entry.categoryID ?? ""
                timestamp = entry.end; recordNow = false
            }
        }
    }
}
