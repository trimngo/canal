import XCTest
@testable import LedgerCore

final class AllocationPlanTests: XCTestCase {
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        ledger.categories = ["work", "teaching", "admin", "music", "health", "home"].map { LedgerCategory(id: $0, name: $0.capitalized) }
        try ledger.moveCategory("teaching", to: "work", writer: "seed")
        return ledger
    }
    func testNewPlansRequireExactly100WithoutChangingOtherGoalsOrHistory() throws {
        var ledger = try fixture()
        let earlier = Date().addingTimeInterval(-86400)
        try ledger.saveTargets(["work": 35, "music": 15], effectiveAt: earlier, writer: "old")
        let before = ledger
        for targets in [["work": 99.0], ["work": 101.0], ["work": Double.nan], ["work": -1.0]] {
            XCTAssertThrowsError(try ledger.saveAllocationPlan(targets, writer: "new"))
            XCTAssertEqual(ledger, before)
        }
        var draft = AllocationPlanDraft(ledger.currentTargets())
        draft.text["music"] = "20"
        XCTAssertEqual(draft.values?["work"], 35)
        draft.text["health"] = "45"
        try ledger.saveAllocationPlan(try XCTUnwrap(draft.values), writer: "new")
        XCTAssertEqual(ledger.currentTargets(), ["work": 35, "music": 20, "health": 45])
        XCTAssertEqual(ledger.currentBudget(at: earlier)?.percentages, ["work": 35, "music": 15])
        XCTAssertEqual(ledger.targetBudgets?.count, 2)
    }
    func testDraftRetainsInvalidValuesAndExplicitRemainderOnlyChangesOneField() throws {
        var draft = AllocationPlanDraft(["work": 40, "music": 20])
        draft.text["health"] = "60"
        XCTAssertFalse(draft.isComplete)
        XCTAssertEqual(draft.total, 120)
        XCTAssertEqual(draft.text["health"], "60")
        draft.useRemaining(for: "health")
        XCTAssertTrue(draft.isComplete)
        XCTAssertEqual(draft.values, ["work": 40, "music": 20, "health": 40])
        draft.text["health"] = "abc"
        XCTAssertNil(draft.values)
        draft.useRemaining(for: "health")
        XCTAssertEqual(draft.values?["health"], 40)
        draft.text["health"] = "40,0"
        XCTAssertTrue(draft.isComplete)
        draft.text["health"] = ""
        XCTAssertEqual(draft.total, 60)
    }
    func testUneditedPrecisionAndArbitraryNumberOfLifeAreas() throws {
        let precise = ["a": 100.0 / 3, "b": 100.0 / 3, "c": 100.0 / 3]
        var draft = AllocationPlanDraft(precise)
        XCTAssertEqual(draft.values, precise)
        XCTAssertFalse(draft.isDirty)
        draft.text["a"] = "33.33333333"
        XCTAssertTrue(draft.isComplete)
        var ledger = Ledger()
        ledger.categories = (0..<12).map { LedgerCategory(id: "area\($0)", name: "Area \($0)") }
        let goals = Dictionary(uniqueKeysWithValues: ledger.categories.map { ($0.id, 100.0 / 12) })
        XCTAssertNoThrow(try ledger.saveAllocationPlan(goals, writer: "test"))
    }
    func testBulkGroupingRetainsSubtreesLogsAndIdeaLabels() throws {
        var ledger = try fixture()
        let stamp = Date().addingTimeInterval(-3600)
        try ledger.saveSample(id: "log", at: stamp, activity: "Preparing class", categoryIDs: ["teaching", "admin"], writer: "test")
        try ledger.addCapture(text: "Class idea", id: "idea", writer: "test")
        try ledger.categorizeCapture(id: "idea", categoryIDs: ["teaching", "admin"], writer: "test")
        let entries = ledger.entries, captures = ledger.captures
        let undo = try ledger.groupCategories(["work", "teaching", "admin"], under: nil, newParentName: "Career", writer: "test")
        let parent = try XCTUnwrap(undo.createdParentID)
        XCTAssertEqual(Set(undo.movedIDs), ["work", "admin"])
        XCTAssertEqual(ledger.categoryParents["work"], parent)
        XCTAssertEqual(ledger.categoryParents["teaching"], "work")
        XCTAssertEqual(ledger.categoryParents["admin"], parent)
        XCTAssertEqual(ledger.entries, entries)
        XCTAssertEqual(ledger.captures, captures)
        let period = ledger.allocation(on: Date())
        XCTAssertEqual(period.total(for: parent, ledger: ledger), period.trackedMinutes, accuracy: 0.0001)
    }
    func testBulkMoveCombinesOnlyMovedRootTargetsAndVersionsBudgetOnce() throws {
        var ledger = try fixture()
        try ledger.saveAllocationPlan(["work": 30, "admin": 10, "music": 25, "health": 35], writer: "test")
        let earlier = ledger.currentBudget()
        let undo = try ledger.groupCategories(["work", "admin"], under: "music", writer: "test")
        XCTAssertEqual(undo.previousTargets["work"], 30)
        XCTAssertEqual(undo.resultingTargets, ["music": 65, "health": 35])
        XCTAssertEqual(ledger.currentTargets(), undo.resultingTargets)
        XCTAssertEqual(ledger.targetBudgets?.count, 2)
        XCTAssertEqual(ledger.targetBudgets?.first, earlier)
        XCTAssertTrue(ledger.canUndoCategoryMove(undo))
        try ledger.undoCategoryMove(undo, writer: "test")
        XCTAssertEqual(ledger.currentTargets(), undo.previousTargets)
        XCTAssertEqual(ledger.targetBudgets?.count, 3)
        XCTAssertNil(ledger.categoryParents["work"])
        XCTAssertEqual(ledger.categoryParents["teaching"], "work")
    }
    func testNewParentReceivesCombinedTargetsAndLegacyIncompleteBudgetStaysReadable() throws {
        var ledger = try fixture()
        try ledger.saveTargets(["work": 30, "admin": 10, "music": 15], writer: "old")
        let undo = try ledger.groupCategories(["work", "admin"], under: nil, newParentName: "Career", writer: "new")
        XCTAssertEqual(ledger.currentTargets()[try XCTUnwrap(undo.createdParentID)], 40)
        XCTAssertEqual(ledger.currentBudget()?.allocated, 55)
        XCTAssertEqual(ledger.currentTargets()["music"], 15)
    }
    func testInvalidBulkMoveIsAtomicIncludingNewParentCreation() throws {
        var ledger = try fixture()
        let before = ledger
        XCTAssertThrowsError(try ledger.groupCategories(["work"], under: "teaching", writer: "test"))
        XCTAssertThrowsError(try ledger.groupCategories(["missing"], under: nil, newParentName: "New", writer: "test"))
        XCTAssertThrowsError(try ledger.groupCategories([], under: "music", writer: "test"))
        XCTAssertThrowsError(try ledger.groupCategories(["work"], under: nil, newParentName: "Music", writer: "test"))
        XCTAssertEqual(ledger, before)
    }
    func testNewLogOrIdeaAncestorConflictsBlockMoveWithoutChangingAnything() throws {
        for log in [true, false] {
            var ledger = try fixture()
            if log {
                try ledger.saveSample(at: Date(), activity: "Both", categoryIDs: ["work", "music"], writer: "test")
            } else {
                try ledger.addCapture(text: "Both", id: "idea", writer: "test")
                try ledger.categorizeCapture(id: "idea", categoryIDs: ["work", "music"], writer: "test")
            }
            let before = ledger
            XCTAssertThrowsError(try ledger.groupCategories(["music", "admin"], under: "work", writer: "test"))
            XCTAssertEqual(ledger, before)
        }
    }
    func testUnrelatedExistingSyncConflictsDoNotBlockMoves() throws {
        var ledger = try fixture()
        try ledger.addCapture(text: "Old labels", id: "idea", writer: "test")
        ledger.captures[0].categoryIDs = ["work", "teaching"]
        XCTAssertNoThrow(try ledger.groupCategories(["music"], under: "health", writer: "test"))
    }
    func testUndoKeepsNewLogsAndUsesTombstoneToConvergeWithAnotherDevice() throws {
        var ledger = try fixture()
        let undo = try ledger.groupCategories(["admin", "music"], under: nil, newParentName: "Personal", writer: "phone")
        var watch = ledger
        try ledger.saveSample(id: "new", at: Date(), activity: "New music log", categoryIDs: ["music"], writer: "watch")
        try ledger.undoCategoryMove(undo, writer: "phone")
        XCTAssertTrue(ledger.entries.contains { $0.id == "new" })
        XCTAssertFalse(ledger.categories.contains { $0.id == undo.createdParentID })
        watch.merge(ledger); ledger.merge(watch)
        XCTAssertEqual(watch, ledger)
        XCTAssertNil(watch.categoryParents["music"])
        XCTAssertFalse(watch.categories.contains { $0.id == undo.createdParentID })
    }
    func testUndoRefusesToDestroyNewParentUseOrOtherCategoryEdits() throws {
        var ledger = try fixture()
        let undo = try ledger.groupCategories(["admin", "music"], under: nil, newParentName: "Personal", writer: "test")
        var withLog = ledger
        try withLog.saveSample(at: Date(), activity: "Direct parent log", categoryIDs: [try XCTUnwrap(undo.createdParentID)], writer: "test")
        XCTAssertFalse(withLog.canUndoCategoryMove(undo))
        let before = withLog
        XCTAssertThrowsError(try withLog.undoCategoryMove(undo, writer: "test"))
        XCTAssertEqual(before, withLog)
        try ledger.saveCategory(id: "health", name: "Wellbeing", writer: "test")
        XCTAssertFalse(ledger.canUndoCategoryMove(undo))
    }
    func testBackupAndFullSyncRetainPlanHierarchyLegacyCommitmentsAndLabels() throws {
        var phone = try fixture()
        try phone.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 60, writer: "old")
        try phone.addCapture(text: "Idea", id: "idea", writer: "old")
        try phone.categorizeCapture(id: "idea", categoryIDs: ["admin"], writer: "old")
        try phone.saveAllocationPlan(["work": 40, "music": 30, "health": 30], writer: "phone")
        let undo = try phone.groupCategories(["admin"], under: "work", writer: "phone")
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        XCTAssertEqual(restored, phone)
        var watch = try fixture(); watch.merge(restored)
        XCTAssertEqual(watch.currentTargets(), phone.currentTargets())
        XCTAssertEqual(watch.categoryParents, phone.categoryParents)
        XCTAssertEqual(watch.captures.first?.categoryIDs, ["admin"])
        XCTAssertEqual(watch.activeWeeklyCommitments.count, 1)
        try phone.undoCategoryMove(undo, writer: "phone")
        watch.merge(phone)
        XCTAssertNil(watch.categoryParents["admin"])
        XCTAssertEqual(watch.currentTargets(), phone.currentTargets())
    }
}
