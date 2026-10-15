import XCTest
@testable import LedgerCore

final class GroupingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testBuiltInDescriptionsGroupWithoutASelectedCategory() throws {
        for (text, group) in [("Preparing classes", "work"), ("using the restroom", "personal"),
                              ("Showering", "personal"), ("Coffee with Alex", "social"),
                              ("Dinner with friends", "social"), ("laundry", "household"),
                              ("watching TV", "leisure"), ("commuting", "travel")] {
            var ledger = Ledger()
            try ledger.saveSample(at: now, activity: text, categoryID: nil, writer: "phone", now: now)
            XCTAssertEqual(ledger.entries[0].categoryID, group, text)
            XCTAssertEqual(ledger.entries[0].categoryAssignment, .automatic)
        }
    }

    func testUnknownAmbiguousNegatedAndSubstringMatchesStayUncategorized() {
        let ledger = Ledger()
        for text in ["quokka activity", "working and showering", "not working", "framework", "restroommate"] {
            XCTAssertNil(ledger.suggestedCategory(for: text), text)
        }
        XCTAssertEqual(ledger.suggestedCategory(for: "restroom"), "personal")
    }

    func testExplicitCorrectionBeatsBuiltInRuleAndTeachesMatchingLogs() throws {
        var ledger = Ledger()
        try ledger.saveSample(id: "earlier", at: now, activity: "Coffee with Alex!", categoryID: nil, writer: "phone", now: now)
        try ledger.saveSample(id: "correction", at: now, activity: "coffee with alex", categoryID: "work", writer: "phone", now: now)
        XCTAssertEqual(ledger.entries.first { $0.id == "earlier" }?.categoryID, "work")
        XCTAssertEqual(ledger.entries.first { $0.id == "earlier" }?.categoryAssignment, .automatic)
        try ledger.saveSample(at: now, activity: "  COFFEE with Alex. ", categoryID: nil, writer: "watch", now: now)
        XCTAssertEqual(ledger.entries.last?.categoryID, "work")
    }

    func testCorrectionDoesNotOverwriteOtherManualAssignments() throws {
        var ledger = Ledger()
        try ledger.saveSample(id: "explicit", at: now, activity: "Lunch", categoryID: "personal", writer: "phone", now: now)
        try ledger.saveSample(id: "newer", at: now, activity: "Lunch", categoryID: "social", writer: "phone", now: now)
        XCTAssertEqual(ledger.entries.first { $0.id == "explicit" }?.categoryID, "personal")
        XCTAssertEqual(ledger.suggestedCategory(for: "lunch"), "social")
    }

    func testNewGroupAndRenamePreserveLearningAndOriginalText() throws {
        var ledger = Ledger()
        try ledger.saveCategory(id: nil, name: "Creative Practice", writer: "phone")
        let id = ledger.categories.last!.id
        try ledger.saveSample(at: now, activity: "Quokka activity", categoryID: id, writer: "phone", now: now)
        try ledger.saveCategory(id: id, name: "Creative Projects", writer: "phone")
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(restored.suggestedCategory(for: "quokka activity"), id)
        XCTAssertEqual(restored.entries[0].activity, "Quokka activity")
        XCTAssertEqual(restored.categories.first { $0.id == id }?.name, "Creative Projects")
    }

    func testRenamingBuiltInGroupKeepsOfflinePhraseRulesWorking() throws {
        var ledger = Ledger()
        try ledger.saveCategory(id: "social", name: "People", writer: "phone")
        XCTAssertEqual(ledger.suggestedCategory(for: "Dinner with friends"), "social")
    }

    func testUpgradeAddsGroupsWithoutChangingLegacyManualChoices() {
        var ledger = Ledger()
        ledger.categories = [LedgerCategory(id: "work", name: "Teaching"), LedgerCategory(id: "personal", name: "Personal"), LedgerCategory(id: "rest", name: "Rest")]
        ledger.entries = [CheckIn(end: now, activity: "Coffee with Alex", categoryID: "work", revision: Revision(counter: 1, writer: "old")),
                          CheckIn(end: now.addingTimeInterval(-60), activity: "using the restroom", categoryID: nil, revision: Revision(counter: 2, writer: "old"))]
        ledger.ensureDefaultGroups(writer: "phone"); ledger.recategorizeAutomatically(writer: "phone")
        XCTAssertEqual(ledger.categories.count, 7)
        XCTAssertEqual(ledger.categories.first { $0.id == "work" }?.name, "Teaching")
        XCTAssertEqual(ledger.entries[0].categoryID, "work")
        XCTAssertEqual(ledger.entries[1].categoryID, "personal")
        let once = ledger
        ledger.ensureDefaultGroups(writer: "phone"); ledger.recategorizeAutomatically(writer: "phone")
        XCTAssertEqual(ledger, once)
    }

    func testExistingCustomDefaultNameDoesNotCreateDuplicateAndSurvivesRename() throws {
        var ledger = Ledger(); ledger.categories.removeAll { $0.id == "social" }
        ledger.categories.append(LedgerCategory(id: "custom-social", name: "Socializing"))
        ledger.ensureDefaultGroups(writer: "phone")
        XCTAssertEqual(ledger.categories.filter { $0.name == "Socializing" }.count, 1)
        XCTAssertEqual(ledger.suggestedCategory(for: "chatting"), "custom-social")
        try ledger.saveCategory(id: "custom-social", name: "People", writer: "phone")
        ledger.ensureDefaultGroups(writer: "phone")
        XCTAssertEqual(ledger.suggestedCategory(for: "Dinner with friends"), "custom-social")
        XCTAssertFalse(ledger.categories.contains { $0.id == "social" })
    }

    func testPhoneAndWatchMergesShareRememberedChoices() throws {
        var phone = Ledger(), watch = Ledger()
        try phone.saveSample(at: now, activity: "Quokka activity", categoryID: "work", writer: "phone", now: now)
        try watch.saveSample(at: now, activity: "quokka activity", categoryID: nil, writer: "watch", now: now)
        watch.merge(phone); watch.recategorizeAutomatically(writer: "watch")
        phone.merge(watch); phone.recategorizeAutomatically(writer: "phone")
        XCTAssertEqual(phone, watch)
        XCTAssertTrue(phone.entries.allSatisfy { $0.categoryID == "work" })
    }

    func testReturningAManualSampleToAutomaticRemovesItsOwnOverride() throws {
        var ledger = Ledger()
        try ledger.saveSample(id: "sample", at: now, activity: "Showering", categoryID: "work", writer: "phone", now: now)
        try ledger.saveSample(id: "sample", at: now, activity: "Showering", categoryID: nil, writer: "phone", now: now)
        XCTAssertEqual(ledger.entries[0].categoryID, "personal")
    }

    func testZeroDurationSampleProducesFinitePercentagesAndNoUnestimatedRow() throws {
        var ledger = Ledger()
        try ledger.saveSample(at: now, activity: "Work", categoryID: nil, writer: "phone", now: now)
        let rows = ledger.breakdown(on: now, now: now)
        XCTAssertTrue(rows.allSatisfy { $0.percent.isFinite && $0.percent == 0 })
        XCTAssertFalse(rows.contains { $0.id == "unlogged" })
    }

    func testGroupNamesMustBeUniqueAndCannotHideTheUncategorizedQueue() throws {
        var ledger = Ledger()
        XCTAssertThrowsError(try ledger.saveCategory(id: nil, name: "Uncategorized", writer: "phone"))
        XCTAssertThrowsError(try ledger.saveCategory(id: nil, name: " work ", writer: "phone"))
    }
}
