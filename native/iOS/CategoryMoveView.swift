import SwiftUI
import LedgerCore

struct CategoryMoveUndoSection: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var error: String?
    var body: some View {
        if store.canUndoCategoryMove {
            Section {
                HStack {
                    Text("Categories grouped").font(.subheadline)
                    Spacer()
                    Button("Undo") {
                        do { try store.undoCategoryMove() } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("categories.undo-move")
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
    }
}

struct CategoryMoveView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let ids: [String]
    var didMove: () -> Void = {}
    @State private var destination = "__new"
    @State private var name = ""
    @State private var error: String?
    private var excluded: Set<String> {
        Set(ids.flatMap { [$0] + store.ledger.descendants(of: $0).map(\.id) })
    }
    private var preview: Result<(Ledger, CategoryMoveUndo), Error> {
        Result {
            var draft = store.ledger
            let undo = try draft.groupCategories(ids, under: destination.hasPrefix("__") ? nil : destination,
                                                newParentName: destination == "__new" ? name : nil, writer: "preview")
            return (draft, undo)
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Group under") {
                    Picker("Parent", selection: $destination) {
                        Text("Create a new parent").tag("__new")
                        Text("Top level (no parent)").tag("__top")
                        ForEach(store.ledger.orderedCategories.filter { !excluded.contains($0.id) }) { category in
                            Text(store.ledger.categoryPath(category.id)).tag(category.id)
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("categories.destination")
                    if destination == "__new" {
                        TextField("Parent name", text: $name).accessibilityIdentifier("categories.new-parent-name")
                    }
                }
                Section("Move preview") {
                    ForEach(ids, id: \.self) { id in Text(store.ledger.categoryPath(id)) }
                    switch preview {
                    case .success(let (draft, undo)):
                        if undo.previousTargets != undo.resultingTargets {
                            Text("Parent goals recalculate from their children. A category becoming a parent uses its children’s total instead of its previous goal.").font(.subheadline)
                            ForEach(Array(Set(undo.previousTargets.keys).union(undo.resultingTargets.keys)).sorted(), id: \.self) { id in
                                if undo.previousTargets[id] != undo.resultingTargets[id] {
                                    HStack {
                                        Text(draft.categories.first { $0.id == id }?.name ?? store.ledger.categoryPath(id))
                                        Spacer()
                                        Text("\(percent(undo.previousTargets[id] ?? 0))% → \(percent(undo.resultingTargets[id] ?? 0))%")
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                        Text("Logs, idea labels, and category identities are kept. Selected parents carry their children with them. You can undo this move.").font(.caption).foregroundStyle(.secondary)
                    case .failure(let problem):
                        if destination != "__new" || !name.isEmpty {
                            Text(problem.localizedDescription).foregroundStyle(.red).font(.subheadline)
                        }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.scrollDismissesKeyboard(.interactively).ledgerInputDismissal()
                .navigationTitle("Group categories").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Move") {
                            do {
                                try store.groupCategories(ids, under: destination.hasPrefix("__") ? nil : destination,
                                                          newParentName: destination == "__new" ? name : nil)
                                didMove(); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.disabled(!isValid).accessibilityIdentifier("categories.apply-move")
                    }
                }
        }
    }
    private var isValid: Bool { if case .success = preview { return store.storageAvailable }; return false }
    private func percent(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
}
