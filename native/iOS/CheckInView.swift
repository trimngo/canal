import SwiftUI
import LedgerCore

struct CheckInView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var saved = false
    @State private var editing: CheckIn?
    @State private var range: HistoryRange = .today
    @State private var start = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var end = Date()
    var body: some View {
        List {
            Section("What are you doing now?") {
                CheckInEditor { saved = true }.id(store.sampleRequestID)
                if saved { Label("Saved. You can change it anytime.", systemImage: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
            Section("Your logs") {
                Picker("Period", selection: $range) {
                    ForEach(HistoryRange.allCases) { Text($0.name).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("logs.range")
                if range == .custom {
                    DatePicker("From", selection: $start, in: ...Date(), displayedComponents: [.date])
                    DatePicker("Through", selection: $end, in: ...Date(), displayedComponents: [.date])
                }
                let samples = store.ledger.history(range: range, start: start, end: end).samples.sorted { $0.end > $1.end }
                DisclosureGroup {
                    ForEach(samples) { entry in
                        Button { editing = entry } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.activity).foregroundStyle(.primary)
                                Text("\(store.dayLabel(entry.end)) · \(store.time(entry.end)) · \(store.categoryNames(for: entry))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("logs.entry.\(entry.id)")
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    do { try store.deleteLog(entry) } catch { store.report(error) }
                                }
                            }
                    }
                } label: { Text("Logs (\(samples.count))").accessibilityIdentifier("today.logs") }
            }
        }.listStyle(.insetGrouped).scrollDismissesKeyboard(.immediately)
            .navigationTitle("Log").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { entry in
                NavigationStack {
                    ScrollView { CheckInEditor(entry: entry) { editing = nil }.padding(20) }
                        .navigationTitle("Edit log").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = nil } } }
                }
            }
    }
}

struct CheckInEditor: View {
    @EnvironmentObject var store: LedgerStore
    var entry: CheckIn? = nil
    var onSave: () -> Void = {}
    @State private var activity = ""
    @State private var categoryIDs: [String] = []
    @State private var recordNow = true
    @State private var timestamp = Date()
    @State private var saving = false
    @FocusState private var focused: Bool
    private var prefix: String { entry == nil ? "checkin" : "edit" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("What are you doing now?", text: $activity, axis: .vertical)
                .lineLimit(1...3).padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                .focused($focused).accessibilityIdentifier("\(prefix).activity")
            if let suggested = store.ledger.suggestedCategory(for: activity) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Suggested: \(store.categoryName(suggested))").font(.subheadline)
                        Spacer()
                        if categoryIDs == [suggested] {
                            Label("Confirmed", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button(categoryIDs.isEmpty ? "Use \(store.categoryName(suggested))" : "Use only \(store.categoryName(suggested))") { categoryIDs = [suggested] }
                                .buttonStyle(.bordered).controlSize(.small)
                                .accessibilityIdentifier("\(prefix).confirm-suggestion")
                        }
                    }
                    Text(categoryIDs.isEmpty ? "Uncategorized until you confirm a group." : "Your chosen group will be saved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if !activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No suggestion yet. You can choose a group or save as Uncategorized.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            CategorySelectionPicker(selection: $categoryIDs).accessibilityIdentifier("\(prefix).category")
            DisclosureGroup("Time") {
                Toggle("Use current time", isOn: $recordNow)
                    .onChange(of: recordNow) { _, value in if !value, entry == nil { timestamp = Date() } }
                if !recordNow {
                    DatePicker("Sample time", selection: $timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
            }.font(.subheadline)
            Button {
                guard !saving else { return }
                saving = true; focused = false
                do {
                    try store.saveSample(id: entry?.id, at: recordNow ? Date() : timestamp,
                                         activity: activity, categoryIDs: categoryIDs)
                    if entry == nil { activity = ""; categoryIDs = [] }
                    onSave()
                } catch { store.report(error) }
                saving = false
            } label: { Text(saving ? "Saving…" : "Save log").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7) }
                .buttonStyle(.borderedProminent)
                .disabled(saving || activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                .accessibilityIdentifier("\(prefix).save")
            if let entry {
                Button("Delete log", role: .destructive) {
                    do { try store.deleteLog(entry); focused = false; onSave() } catch { store.report(error) }
                }.frame(maxWidth: .infinity).padding(.top, 8).accessibilityIdentifier("edit.delete")
            }
        }.ledgerInputDismissal().onDisappear { focused = false }.onAppear {
            if let entry {
                activity = entry.activity; categoryIDs = store.ledger.confirmedCategoryIDs(for: entry)
                timestamp = entry.end; recordNow = false
            } else if let draft = store.quickReplyDraft {
                activity = draft; store.quickReplyDraft = nil
            }
        }.onChange(of: activity) { old, new in
            if entry == nil, OfflineGrouping.normalized(old) != OfflineGrouping.normalized(new) { categoryIDs = [] }
        }
    }
}
