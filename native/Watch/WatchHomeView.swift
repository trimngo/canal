import SwiftUI
import LedgerCore

struct WatchHomeView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var activity = ""
    @State private var categoryID = ""
    @State private var capture = ""
    @State private var saved = false
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What were you doing?").font(.headline)
                    Text(store.interval(store.selectedSlot)).font(.caption).foregroundStyle(.secondary)
                    TextField("Dictate an answer", text: $activity)
                    Picker("Category", selection: $categoryID) {
                        Text("Later").tag("")
                        ForEach(store.ledger.categories) { Text($0.name).tag($0.id) }
                    }
                    Button(saved ? "Saved ✓" : "Save check-in") {
                        do {
                            try store.saveCheckIn(end: store.selectedSlot, activity: activity, categoryID: categoryID.isEmpty ? nil : categoryID)
                            saved = true
                        } catch { store.report(error) }
                    }.buttonStyle(.borderedProminent).disabled(activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                    Button("Latest 15 minutes") { store.selectedSlot = Ledger.slotEnd(at: Date()); load() }
                        .font(.caption)
                }.padding(.horizontal, 4)
            }.tag(0)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Get it out of your head.").font(.headline)
                    TextField("Capture a thought", text: $capture)
                    Button("Save to inbox") {
                        do { try store.addCapture(capture); capture = "" } catch { store.report(error) }
                    }.buttonStyle(.borderedProminent).disabled(capture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                    Text("You can review it on your phone.").font(.caption).foregroundStyle(.secondary)
                }
            }.tag(1)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today").font(.headline)
                    ForEach(store.ledger.breakdown(on: Date())) { row in
                        HStack { Text(row.name); Spacer(); Text("\(row.percent, specifier: "%.0f")%").foregroundStyle(.secondary) }.font(.caption)
                    }
                    Text("Of 24 hours").font(.caption2).foregroundStyle(.secondary)
                    Button("Sync") { store.refresh() }
                }
            }.tag(2)
        }.tabViewStyle(.verticalPage)
            .onAppear { load() }
            .onChange(of: store.selectedSlot) { _, _ in tab = 0; load() }
    }
    private func load() {
        activity = store.entry(at: store.selectedSlot)?.activity ?? ""
        categoryID = store.entry(at: store.selectedSlot)?.categoryID ?? ""
        saved = false
    }
}
