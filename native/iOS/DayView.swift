import SwiftUI
import LedgerCore

struct DayView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var day = Date()
    @State private var onlyUncategorized = false
    @State private var editing: CheckIn?
    var rows: [BreakdownRow] { store.ledger.breakdown(on: day) }
    var entries: [CheckIn] { store.ledger.entries(on: day).filter { !onlyUncategorized || $0.categoryID == nil } }
    var body: some View {
        List {
            Section {
                DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: [.date])
            }
            Section("Where your time went") {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(row.name); Spacer()
                            Text("\(row.minutes / 60)h \(row.minutes % 60)m · \(row.percent, specifier: "%.1f")%")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(1, row.percent / 100))
                    }.padding(.vertical, 4)
                }
            }
            Section {
                Toggle("Only uncategorized", isOn: $onlyUncategorized)
                if entries.isEmpty { Text("No check-ins here yet.").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    Button { editing = entry } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.activity).foregroundStyle(.primary)
                            Text("\(store.interval(entry.end)) · \(store.categoryName(entry.categoryID))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: { Text("Your log") } footer: {
                Text("Percentages use a fixed 24-hour day. Not logged includes missed intervals and, today, time still ahead. Daylight-saving days can contain 23 or 25 actual hours.")
            }
        }.navigationTitle("My day")
            .sheet(item: $editing) { entry in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(store.interval(entry.end)).font(.headline)
                        CheckInEditor(end: entry.end) { editing = nil }
                        Spacer()
                    }.padding(24).navigationTitle("Edit check-in").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } } }
                }
            }
    }
}
