import XCTest
@testable import LedgerCore

final class GroupingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testBuiltInDescriptionsSuggestWithoutAssigning() throws {
        for (text, group) in [("Preparing classes", "work"), ("using the restroom", "personal"),
                              ("Showering", "personal"), ("Coffee with Alex", "social"),
                              ("Dinner with friends", "social"), ("laundry", "household"),
                              ("watching TV", "leisure"), ("commuting", "travel")] {
            var ledger = Ledger()
            try ledger.saveSample(at: now, activity: text, categoryID: nil, writer: "phone", now: now)
            XCTAssertNil(ledger.entries[0].categoryID, text)
            XCTAssertEqual(ledger.suggestedCategory(for: text), group, text)
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
        XCTAssertNil(ledger.entries.first { $0.id == "earlier" }?.categoryID)
        XCTAssertEqual(ledger.entries.first { $0.id == "earlier" }?.categoryAssignment, .automatic)
        try ledger.saveSample(at: now, activity: "  COFFEE with Alex. ", categoryID: nil, writer: "watch", now: now)
        XCTAssertNil(ledger.entries.last?.categoryID)
        XCTAssertEqual(ledger.suggestedCategory(for: "coffee with alex"), "work")
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
        ledger.ensureDefaultGroups(writer: "phone"); ledger.prepareGroupSuggestions(writer: "phone")
        XCTAssertEqual(ledger.categories.count, 7)
        XCTAssertEqual(ledger.categories.first { $0.id == "work" }?.name, "Teaching")
        XCTAssertEqual(ledger.entries[0].categoryID, "work")
        XCTAssertNil(ledger.entries[1].categoryID)
        XCTAssertEqual(ledger.suggestedCategory(for: ledger.entries[1].activity), "personal")
        let once = ledger
        ledger.ensureDefaultGroups(writer: "phone"); ledger.prepareGroupSuggestions(writer: "phone")
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
        watch.merge(phone); watch.prepareGroupSuggestions(writer: "watch")
        phone.merge(watch); phone.prepareGroupSuggestions(writer: "phone")
        XCTAssertEqual(phone, watch)
        XCTAssertEqual(phone.entries.filter { phone.confirmedCategoryID(for: $0) == "work" }.count, 1)
        XCTAssertEqual(phone.entries.filter { phone.confirmedCategoryID(for: $0) == nil }.count, 1)
        XCTAssertEqual(phone.suggestedCategory(for: "quokka activity"), "work")
    }

    func testRemovingAConfirmedGroupLeavesOnlyASuggestion() throws {
        var ledger = Ledger()
        try ledger.saveSample(id: "sample", at: now, activity: "Showering", categoryID: "work", writer: "phone", now: now)
        try ledger.saveSample(id: "sample", at: now, activity: "Showering", categoryID: nil, writer: "phone", now: now)
        XCTAssertNil(ledger.entries[0].categoryID)
        XCTAssertEqual(ledger.suggestedCategory(for: "Showering"), "personal")
    }

    func testZeroDurationSampleProducesFinitePercentagesAndNoUnestimatedRow() throws {
        var ledger = Ledger()
        try ledger.saveSample(at: now, activity: "Work", categoryID: nil, writer: "phone", now: now)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rows = ledger.breakdown(on: now, now: now, calendar: calendar)
        XCTAssertTrue(rows.allSatisfy { $0.percent.isFinite && $0.percent == 0 })
        XCTAssertFalse(rows.contains { $0.id == "unlogged" })
    }

    func testGroupNamesMustBeUniqueAndCannotHideTheUncategorizedQueue() throws {
        var ledger = Ledger()
        XCTAssertThrowsError(try ledger.saveCategory(id: nil, name: "Uncategorized", writer: "phone"))
        XCTAssertThrowsError(try ledger.saveCategory(id: nil, name: " work ", writer: "phone"))
    }

    func testOldAutomaticAssignmentsAreUnconfirmedAndMigrationPreservesManualChoices() {
        var ledger = Ledger()
        let old = CheckIn(end: now.addingTimeInterval(-3600), activity: "Working on app", categoryID: "work", revision: Revision(counter: 1, writer: "old"), sampleID: "automatic", categoryAssignment: .automatic)
        ledger.entries = [old]
        XCTAssertNil(ledger.confirmedCategoryID(for: old))
        let rows = ledger.breakdown(on: now, now: now)
        XCTAssertEqual(rows.first { $0.id == "work" }?.minutes, 0)
        XCTAssertEqual(rows.first { $0.id == "uncategorized" }?.percent, 100)
        let manual = CheckIn(end: now, activity: "Confirmed work", categoryID: "work", revision: Revision(counter: 2, writer: "old"), sampleID: "manual", categoryAssignment: .manual)
        ledger.entries.append(manual)
        ledger.prepareGroupSuggestions(writer: "phone")
        XCTAssertNil(ledger.entries[0].categoryID)
        XCTAssertEqual(ledger.entries[0].activity, old.activity)
        XCTAssertEqual(ledger.entries[0].end, old.end)
        XCTAssertEqual(ledger.entries[1], manual)
        XCTAssertEqual(ledger.suggestedCategory(for: old.activity), "work")
    }

    func testBatchConfirmationOnlyAffectsRequestedUnconfirmedMatchingDescriptions() throws {
        var ledger = Ledger()
        try ledger.saveSample(id: "one", at: now, activity: "Showering", categoryID: nil, writer: "phone", now: now)
        try ledger.saveSample(id: "two", at: now, activity: "showering!", categoryID: nil, writer: "phone", now: now)
        try ledger.saveSample(id: "manual", at: now, activity: "Showering", categoryID: "rest", writer: "phone", now: now)
        try ledger.saveSample(id: "other", at: now, activity: "Working", categoryID: nil, writer: "phone", now: now)
        try ledger.confirmCategory(for: "one", categoryID: "personal", includeMatching: true, writer: "phone")
        XCTAssertEqual(ledger.entries.first { $0.id == "one" }?.categoryID, "personal")
        XCTAssertEqual(ledger.entries.first { $0.id == "two" }?.categoryID, "personal")
        XCTAssertEqual(ledger.entries.first { $0.id == "manual" }?.categoryID, "rest")
        XCTAssertNil(ledger.entries.first { $0.id == "other" }?.categoryID)
        XCTAssertTrue(ledger.entries.filter { $0.categoryID == "personal" }.allSatisfy { $0.categoryAssignment == .manual })
    }

    func testConfirmationPreservesOriginalTextAndTimeAndDoesNotConfirmFutureSamples() throws {
        var ledger = Ledger()
        let original = CheckIn(end: now, activity: "  Working on app!  ", categoryID: nil, revision: Revision(counter: 1, writer: "old"), sampleID: "sample")
        ledger.entries = [original]
        try ledger.confirmCategory(for: original.id, categoryID: "work", writer: "phone")
        XCTAssertEqual(ledger.entries[0].activity, original.activity)
        XCTAssertEqual(ledger.entries[0].end, original.end)
        try ledger.saveSample(at: now, activity: "Working on app", categoryID: nil, writer: "phone", now: now)
        XCTAssertNil(ledger.entries.last?.categoryID)
        XCTAssertEqual(ledger.suggestedCategory(for: "Working on app"), "work")
    }
}
