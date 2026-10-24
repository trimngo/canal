import SwiftUI
import LedgerCore

struct AutomaticMatchingView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var phrase = ""
    @State private var categoryPhrase = ""
    @State private var selectedCategory = ""
    @State private var testText = ""
    private var phrases: [String] { store.ledger.settings.effectiveUrgencyPhrases }
    private var rules: [CategoryMatchRule] { store.ledger.settings.categoryMatchRules ?? [] }
    var body: some View {
        Form {
            Section {
                NavigationLink("Urgency phrases (\(phrases.count))") { urgencyPhrases }
                    .accessibilityIdentifier("matching.urgency")
                Picker("Categories", selection: Binding(get: { store.ledger.settings.effectiveCategoryMatching }, set: { value in
                    update { $0.categoryMatching = value }
                })) {
                    ForEach(CategoryMatching.allCases) { Text($0.name).tag($0) }
                }.accessibilityIdentifier("matching.coverage")
            } header: { Text("Automatic matching") } footer: {
                Text("Works offline. Broader suggestions categorize more entries and may make more mistakes. Suggested categories count toward totals and remain marked for review. Your confirmed choices and corrections teach future matches across logs and Inbox ideas; automatic guesses never teach themselves.")
            }
            Section {
                ForEach(rules) { rule in
                    VStack(alignment: .leading, spacing: 4) {
                        InlineEntryText(text: rule.phrase, identifier: "matching.rule.\(rule.id)") { value in
                            try saveRule(rule, phrase: value, categoryID: rule.categoryID)
                        }
                        categoryMenu(rule.categoryID) { id in
                            do { try saveRule(rule, phrase: rule.phrase, categoryID: id) } catch { store.report(error) }
                        }
                    }
                }.onDelete { indices in update { $0.categoryMatchRules = rules.enumerated().filter { !indices.contains($0.offset) }.map(\.element) } }
                TextField("Phrase, e.g. guitar", text: $categoryPhrase).accessibilityIdentifier("matching.new-rule-phrase")
                categoryMenu(selectedCategory) { selectedCategory = $0 }
                    .accessibilityIdentifier("matching.new-rule-category")
                Button("Add category rule") {
                    let rule = CategoryMatchRule(phrase: categoryPhrase.trimmingCharacters(in: .whitespacesAndNewlines), categoryID: selectedCategory)
                    update { $0.categoryMatchRules = rules + [rule] }; categoryPhrase = ""
                }.disabled(categoryPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCategory.isEmpty)
                    .accessibilityIdentifier("matching.add-rule")
            } header: { Text("Category phrases") } footer: {
                Text("A matching phrase assigns its category to unconfirmed entries. Several matching rules can assign several categories. More specific child categories take precedence over their parents. Confirmed entries are kept as you chose them.")
            }
            Section("Try a phrase") {
                TextField("Text to check", text: $testText, axis: .vertical).accessibilityIdentifier("matching.test")
                if !testText.isEmpty {
                    let urgent = OfflineInboxUrgency.suggestion(text: testText, phrases: phrases)
                    Text(urgent.map { "Suggested ASAP · \($0.reason.rawValue)" } ?? "No automatic urgency")
                        .font(.subheadline).accessibilityIdentifier("matching.test-urgency")
                    let result = OfflineCategoryModel(ledger: store.ledger, matching: store.ledger.settings.effectiveCategoryMatching).suggest(testText)
                    if let result {
                        Text(result.categoryIDs.map { store.ledger.categoryPath($0) }.joined(separator: ", "))
                            .accessibilityIdentifier("matching.test-categories")
                        Text(result.reason).font(.caption).foregroundStyle(.secondary)
                    } else { Text("No phrase or learned-word category match").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle("Automatic matching").scrollDismissesKeyboard(.interactively).ledgerInputDismissal()
    }
    private var urgencyPhrases: some View {
        List {
            Section {
                ForEach(Array(phrases.enumerated()), id: \.offset) { index, value in
                    InlineEntryText(text: value, identifier: "matching.urgency-phrase.\(index)") { replacement in
                        var settings = store.ledger.settings
                        var values = settings.effectiveUrgencyPhrases
                        guard values.indices.contains(index), values[index] == value else { return }
                        values[index] = replacement; settings.urgencyPhrases = values
                        try store.saveSettings(settings)
                    }
                }.onDelete { indices in update { $0.urgencyPhrases = phrases.enumerated().filter { !indices.contains($0.offset) }.map(\.element) } }
            } footer: {
                Text("Swipe to remove a phrase or tap to edit. Built-in phrases recognize common wording variations. Custom phrases match whole words, ignoring punctuation and capitalization. No date on an individual idea suppresses its automatic urgency.")
            }
            Section {
                TextField("New phrase", text: $phrase).accessibilityIdentifier("matching.new-urgency-phrase")
                Button("Add phrase") {
                    update { $0.urgencyPhrases = phrases + [phrase.trimmingCharacters(in: .whitespacesAndNewlines)] }; phrase = ""
                }.disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("matching.add-urgency-phrase")
                Button("Restore default phrases") { update { $0.urgencyPhrases = nil } }
            }
        }.navigationTitle("Urgency phrases").scrollDismissesKeyboard(.interactively).ledgerInputDismissal()
    }
    private func categoryMenu(_ id: String, choose: @escaping (String) -> Void) -> some View {
        Picker("Category", selection: Binding(get: { id }, set: choose)) {
            Text("Choose category").tag("")
            ForEach(store.ledger.orderedCategories) { category in
                Text(store.ledger.categoryPath(category.id)).tag(category.id)
                    .accessibilityIdentifier("matching.category-option.\(category.id)")
            }
        }.pickerStyle(.navigationLink)
    }
    private func saveRule(_ rule: CategoryMatchRule, phrase: String, categoryID: String) throws {
        var settings = store.ledger.settings, values = rules
        guard let index = values.firstIndex(where: { $0.id == rule.id }) else { return }
        values[index].phrase = phrase; values[index].categoryID = categoryID
        settings.categoryMatchRules = values; try store.saveSettings(settings)
    }
    private func update(_ edit: (inout Settings) -> Void) {
        var settings = store.ledger.settings; edit(&settings)
        do { try store.saveSettings(settings) } catch { store.report(error) }
    }
}
