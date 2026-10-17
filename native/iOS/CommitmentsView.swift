import SwiftUI
import UIKit
import LedgerCore

struct CommitmentsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var adding = false
    @State private var editing: WeeklyCommitment?
    @State private var managingCategories = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let week = store.ledger.commitmentWeek(now: context.date)
            List {
                Section {
                    if week.rows.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Make time for what matters").font(.headline)
                            Text("Choose a category and a minimum amount of time to spend on it each week.").foregroundStyle(.secondary)
                            Button("Add a weekly commitment") { adding = true }
                                .accessibilityIdentifier("commitments.empty.add")
                        }.padding(.vertical, 8)
                    } else {
                        ForEach(week.rows) { row in
                            Button { editing = row.commitment } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(row.name).font(.headline)
                                        Spacer(minLength: 8)
                                        Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text("\(store.duration(row.minutes.rounded(.down))) of \(store.duration(Double(row.commitment.minimumMinutes))) this week")
                                        .font(.subheadline).monospacedDigit()
                                    ProgressView(value: min(1, row.minutes / Double(row.commitment.minimumMinutes)))
                                    if row.isMet {
                                        Label("Minimum met", systemImage: "checkmark.circle.fill").font(.subheadline)
                                    } else {
                                        Text("\(store.duration(row.remainingMinutes.rounded(.up))) remaining").font(.subheadline.bold())
                                    }
                                }.foregroundStyle(.primary).padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("commitments.edit.\(row.id)")
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This week").font(.headline)
                        Text(weekLabel(week.interval)).font(.caption)
                    }.textCase(nil).accessibilityIdentifier("commitments.week")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if week.loggedMinutes == 0 { Text("No logged time this week yet.") }
                        Text("Monday–Sunday. Progress uses your estimated activity time, including subcategories. Days without logs add no time.")
                    }
                }
            }.listStyle(.insetGrouped).listSectionSpacing(12).scrollDismissesKeyboard(.immediately)
        }
        .navigationTitle("Commitments").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { adding = true } label: { Label("Add commitment", systemImage: "plus") }
                    .accessibilityIdentifier("commitments.add")
                Menu {
                    Button("Categories") { managingCategories = true }
                    NavigationLink("Percentage targets", value: LedgerScreen.targets)
                        .accessibilityIdentifier("commitments.percentage-targets")
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More commitment options").accessibilityIdentifier("commitments.more")
            }
        }
        .sheet(isPresented: $adding) { CommitmentEditorView() }
        .sheet(item: $editing) { CommitmentEditorView(commitment: $0) }
        .sheet(isPresented: $managingCategories) { GroupManagerView() }
    }

    private func weekLabel(_ interval: DateInterval) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = store.ledger.reportingCalendar().timeZone
        return "\(interval.start.formatted(style)) – \(interval.end.addingTimeInterval(-1).formatted(style))"
    }
}

private struct CommitmentEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    var commitment: WeeklyCommitment?
    @State private var categoryID = ""
    @State private var hours: String
    @State private var minutes: String
    @State private var error: String?
    @State private var confirmingRemoval = false
    @State private var managingCategories = false
    private enum TimeField: Hashable { case hours, minutes }
    @FocusState private var focusedTime: TimeField?

    init(commitment: WeeklyCommitment? = nil) {
        self.commitment = commitment
        _hours = State(initialValue: String((commitment?.minimumMinutes ?? 60) / 60))
        _minutes = State(initialValue: String((commitment?.minimumMinutes ?? 60) % 60))
    }
    private var availableCategories: [LedgerCategory] {
        let used = Set(store.ledger.activeWeeklyCommitments.map(\.categoryID))
        return store.ledger.orderedCategories.filter { !used.contains($0.id) || $0.id == commitment?.categoryID }
    }
    private var minimum: Int? {
        guard let h = Int(hours.isEmpty ? "0" : hours), let m = Int(minutes.isEmpty ? "0" : minutes),
              (0...168).contains(h), (0...59).contains(m), (1...10080).contains(h * 60 + m) else { return nil }
        return h * 60 + m
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    if let commitment {
                        Text(store.ledger.categoryPath(commitment.categoryID))
                    } else if availableCategories.isEmpty {
                        Text("All your categories already have a commitment, or no categories have been created yet.").foregroundStyle(.secondary)
                    } else {
                        Picker("Category", selection: $categoryID) {
                            ForEach(availableCategories) { category in
                                Text(store.ledger.categoryPath(category.id)).tag(category.id)
                            }
                        }.pickerStyle(.menu).accessibilityIdentifier("commitment.category")
                    }
                    if commitment == nil { Button("Manage categories") { managingCategories = true } }
                }
                Section {
                    HStack {
                        TextField("Hours", text: $hours).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .focused($focusedTime, equals: .hours)
                            .accessibilityIdentifier("commitment.hours")
                        Text("h").foregroundStyle(.secondary)
                        TextField("Minutes", text: $minutes).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .focused($focusedTime, equals: .minutes)
                            .accessibilityIdentifier("commitment.minutes")
                        Text("min").foregroundStyle(.secondary)
                    }
                    if minimum == nil { Text("Enter a time greater than zero, up to 168 hours. Minutes must be between 0 and 59.").font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Weekly minimum") } footer: {
                    Text("Time assigned to this category and its subcategories counts automatically. Changing the minimum keeps your activity logs.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if commitment != nil {
                    Section {
                        Button("Remove commitment", role: .destructive) { UIApplication.shared.dismissLedgerKeyboard(); confirmingRemoval = true }
                            .accessibilityIdentifier("commitment.remove")
                    }
                }
            }.scrollDismissesKeyboard(.immediately).ledgerInputDismissal()
                .navigationTitle(commitment == nil ? "New commitment" : "Edit commitment").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.disabled(minimum == nil || !availableCategories.contains { $0.id == categoryID })
                            .accessibilityIdentifier("commitment.save")
                    }
                }
                .onAppear { selectInitialCategory() }
                .onChange(of: focusedTime) { _, field in
                    guard field != nil else { return }
                    DispatchQueue.main.async {
                        UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.selectAll(_:)), to: nil, from: nil, for: nil)
                    }
                }
                .onChange(of: availableCategories.map(\.id)) { _, _ in selectInitialCategory() }
                .confirmationDialog("Remove this weekly commitment?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                    Button("Remove commitment", role: .destructive) {
                        do { try store.saveWeeklyCommitment(categoryID: categoryID, minimumMinutes: nil); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                } message: { Text("Your category and activity logs will be kept.") }
                .sheet(isPresented: $managingCategories) { GroupManagerView() }
        }
    }
    private func selectInitialCategory() {
        if let commitment { categoryID = commitment.categoryID }
        else if !availableCategories.contains(where: { $0.id == categoryID }) { categoryID = availableCategories.first?.id ?? "" }
    }
    private func save() {
        guard let minimum else { return }
        UIApplication.shared.dismissLedgerKeyboard()
        do { try store.saveWeeklyCommitment(categoryID: categoryID, minimumMinutes: minimum); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
