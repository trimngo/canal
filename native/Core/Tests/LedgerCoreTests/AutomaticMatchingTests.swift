import XCTest
@testable import LedgerCore

final class AutomaticMatchingTests: XCTestCase {
    func fixture() -> Ledger {
        var ledger = Ledger()
        ledger.categories = [LedgerCategory(id: "music", name: "Music"), LedgerCategory(id: "work", name: "Work")]
        return ledger
    }
    func testBroaderMatchingLearnsFromOneConfirmedChoiceWithoutTeachingItself() throws {
        var ledger = fixture()
        let idea = try ledger.addCapture(text: "Practicing cello", id: "a", writer: "p")
        try ledger.categorizeCapture(id: idea.id, categoryIDs: ["music"], writer: "p")
        XCTAssertNil(OfflineCategoryModel(ledger: ledger).suggest("Tuning cello"))
        XCTAssertEqual(OfflineCategoryModel(ledger: ledger, matching: .broader).suggest("Tuning cello")?.categoryIDs, ["music"])
        let second = try ledger.addCapture(text: "Tuning cello", id: "b", writer: "p")
        let suggestion = CategorySuggestion(categoryIDs: ["music"], reason: "Learned", sourceText: second.text)
        try ledger.suggestCategories(suggestion, captureID: second.id, writer: "p")
        XCTAssertEqual(OfflineCategoryModel(ledger: ledger, matching: .broader).examples.count, 1)
        try ledger.categorizeCapture(id: idea.id, categoryIDs: ["work"], writer: "p")
        XCTAssertEqual(OfflineCategoryModel(ledger: ledger, matching: .broader).suggest("Tuning cello")?.categoryIDs, ["work"])
    }
    func testPhraseRulesWorkAcrossLogsAndIdeasAndPreferSpecificCategory() throws {
        var ledger = fixture()
        ledger.categories.append(LedgerCategory(id: "guitar", name: "Guitar"))
        try ledger.moveCategory("guitar", to: "music", writer: "p")
        ledger.settings.categoryMatchRules = [.init(phrase: "rehearsal", categoryID: "music"), .init(phrase: "rehearsal", categoryID: "guitar"), .init(phrase: "slides", categoryID: "work")]
        let model = OfflineCategoryModel(ledger: ledger, matching: .broader)
        XCTAssertEqual(model.suggest("Rehearsal with slides")?.categoryIDs, ["guitar", "work"])
        XCTAssertNil(model.suggest("Slideshows"))
        ledger.settings.categoryMatchRules?.append(.init(phrase: "AI", categoryID: "work"))
        XCTAssertEqual(OfflineCategoryModel(ledger: ledger, matching: .broader).suggest("AI")?.categoryIDs, ["work"])
    }
    func testDeletedCategoryRulesCannotAssignObsoleteCategory() {
        var ledger = fixture(); ledger.settings.categoryMatchRules = [.init(phrase: "cello", categoryID: "missing")]
        XCTAssertNil(OfflineCategoryModel(ledger: ledger, matching: .broader).suggest("cello"))
    }
    func testBroaderMatchingUsesWeakerUniqueSemanticEvidenceButAbstainsOnTie() {
        let model = OfflineCategoryModel(ledger: fixture(), matching: .broader)
        XCTAssertEqual(model.suggest("Practicing scales", semantic: [.init(categoryIDs: ["music"], similarity: 0.76)])?.categoryIDs, ["music"])
        XCTAssertNil(model.suggest("Practicing scales", semantic: [.init(categoryIDs: ["music"], similarity: 0.76), .init(categoryIDs: ["work"], similarity: 0.75)]))
    }
    func testBroaderVocabularyCanRecognizeMusicWithoutTrainingHistory() {
        XCTAssertEqual(OfflineCategoryModel(ledger: fixture(), matching: .broader).suggest("Playing piano")?.categoryIDs, ["music"])
    }
}
