import SwiftUI
import LedgerCore

struct CheckInView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var showIntervals = false
    @State private var saved = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("One moment at a time.").font(.subheadline).foregroundStyle(.secondary)
            Text("What were you doing?").font(.largeTitle.bold())
            Button { showIntervals = true } label: {
                Label(store.interval(store.selectedSlot), systemImage: "clock").font(.headline)
            }
            Button("Use latest 15 minutes") { store.selectedSlot = Ledger.slotEnd(at: Date()) }
                .font(.subheadline)
            CheckInEditor(end: store.selectedSlot) { saved = true }.id(store.selectedSlot)
            if saved { Label("Saved. You can change it anytime.", systemImage: "checkmark.circle.fill").foregroundStyle(.tint) }
            Spacer()
            Text("Each answer covers 15 minutes. Missing one is okay.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24).navigationTitle("Check in").navigationBarTitleDisplayMode(.inline)
        .disabled(!store.storageAvailable)
        .onChange(of: store.selectedSlot) { _, _ in saved = false }
        .sheet(isPresented: $showIntervals) {
            NavigationStack { IntervalPicker { end in store.selectedSlot = end; showIntervals = false } }
        }
    }
}

struct CheckInEditor: View {
    @EnvironmentObject var store: LedgerStore
    let end: Date
    var onSave: () -> Void = {}
    @State private var activity = ""
    @State private var categoryID = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TextField("Preparing classes, walking, resting…", text: $activity, axis: .vertical)
                .lineLimit(3...6).padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                .focused($focused).accessibilityIdentifier("checkin.activity")
            Picker("Category", selection: $categoryID) {
                Text("Categorize later").tag("")
                ForEach(store.ledger.categories) { Text($0.name).tag($0.id) }
            }.pickerStyle(.menu)
            Button {
                do {
                    try store.saveCheckIn(end: end, activity: activity, categoryID: categoryID.isEmpty ? nil : categoryID)
                    focused = false; onSave()
                } catch { store.report(error) }
            } label: { Text("Save check-in").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10) }
                .buttonStyle(.borderedProminent)
                .disabled(activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                .accessibilityIdentifier("checkin.save")
        }
        .onAppear { load() }
        .onChange(of: end) { _, _ in load() }
    }
    private func load() {
        activity = store.entry(at: end)?.activity ?? ""
        categoryID = store.entry(at: end)?.categoryID ?? ""
    }
}

struct IntervalPicker: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    @State private var day = Date()
    var select: (Date) -> Void
    var body: some View {
        List {
            DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: [.date])
            ForEach(Ledger.completedSlots(on: day).reversed(), id: \.self) { end in
                Button { select(end) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(store.interval(end))
                            Text(store.entry(at: end)?.activity ?? "Not logged").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.entry(at: end) != nil { Image(systemName: "checkmark") }
                    }
                }
            }
        }.navigationTitle("Choose an interval")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
}
