import XCTest
@testable import LedgerCore

final class AllocationGoalTests: XCTestCase {
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"), LedgerCategory(id: "life", name: "Energy giving"), LedgerCategory(id: "music", name: "Music"), LedgerCategory(id: "guitar", name: "Guitar"), LedgerCategory(id: "rest", name: "Rest")]
        for (id, parent) in [("teaching", "work"), ("music", "life"), ("guitar", "music"), ("rest", "life")] {
            try ledger.moveCategory(id, to: parent, writer: "fixture")
        }
        return ledger
    }
    func testParentsAlwaysSumChildrenAtEveryLevelWithoutDoubleCounting() throws {
        var ledger = try fixture()
        // Ignore independent parent values: only leaf goals determine the plan.
        try ledger.saveAllocationGoals(["work": 99, "teaching": 50, "life": 99, "music": 99, "guitar": 30, "rest": 20], writer: "phone")
        XCTAssertEqual(ledger.currentGoals(), ["work": 50, "teaching": 50, "life": 50, "music": 30, "guitar": 30, "rest": 20])
        XCTAssertEqual(ledger.currentBudget()?.allocated, 100)
        XCTAssertEqual(ledger.currentBudget()?.unallocated, 0)
        XCTAssertTrue(ledger.allocationGoalBalance(ledger.currentGoals()).isComplete)
        XCTAssertEqual(ledger.currentTargets(), ["work": 50, "life": 50])
        XCTAssertEqual(ledger.currentBudget()?.leafGoalPercentages, ["teaching": 50, "guitar": 30, "rest": 20])
    }
    func testEditingChildImmediatelyRecalculatesAncestorsAndPreservesOtherBranches() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["teaching": 50, "guitar": 30, "rest": 20], writer: "phone")
        try ledger.updateAllocationGoal(categoryID: "guitar", percentage: 40, writer: "phone")
        XCTAssertEqual(ledger.currentGoals(), ["work": 50, "teaching": 50, "life": 60, "music": 40, "guitar": 40, "rest": 20])
        XCTAssertEqual(ledger.currentBudget()?.allocated, 110)
        XCTAssertFalse(ledger.allocationGoalBalance(ledger.currentGoals()).isComplete)
        try ledger.updateAllocationGoal(categoryID: "rest", percentage: 10, writer: "phone")
        XCTAssertTrue(ledger.allocationGoalBalance(ledger.currentGoals()).isComplete)
        try ledger.updateAllocationGoal(categoryID: "guitar", percentage: nil, writer: "phone")
        XCTAssertNil(ledger.currentGoals()["guitar"])
        XCTAssertNil(ledger.currentGoals()["music"])
        XCTAssertEqual(ledger.currentGoals()["life"], 10)
        XCTAssertEqual(ledger.currentGoals()["work"], 50)
    }
    func testUnconfiguredBranchesHaveNoGoalOrFeedbackTarget() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["guitar": 20], writer: "phone")
        XCTAssertNil(ledger.currentGoals()["work"])
        XCTAssertNil(ledger.currentGoals()["teaching"])
        XCTAssertNil(ledger.currentGoals()["rest"])
        XCTAssertEqual(ledger.currentGoals()["life"], 20)
        XCTAssertEqual(ledger.currentBudget()?.unallocated, 80)
    }
    func testCalculatedParentMayExceed100WhileIndividualLeafInputsStayValid() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["guitar": 80, "rest": 70], writer: "phone")
        XCTAssertEqual(ledger.currentGoals()["life"], 150)
        XCTAssertEqual(ledger.currentBudget()?.unallocated, -50)
        let before = ledger
        try ledger.saveAllocationGoals(ledger.currentGoals(), writer: "phone")
        XCTAssertEqual(ledger, before)
    }
    func testParentCannotBeEditedIndependentlyAndValidationIsAtomic() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["teaching": 100], writer: "phone")
        let before = ledger
        try ledger.updateAllocationGoal(categoryID: "teaching", percentage: 100, writer: "phone")
        XCTAssertEqual(ledger, before)
        for id in ["work", "music", "life"] {
            XCTAssertThrowsError(try ledger.updateAllocationGoal(categoryID: id, percentage: 10, writer: "phone"))
            XCTAssertEqual(ledger, before)
        }
        for value in [Double.nan, .infinity, -1, 101] {
            XCTAssertThrowsError(try ledger.updateAllocationGoal(categoryID: "guitar", percentage: value, writer: "phone"))
            XCTAssertEqual(ledger, before)
        }
        XCTAssertThrowsError(try ledger.updateAllocationGoal(categoryID: "missing", percentage: 5, writer: "phone"))
    }
    func testDirectActualTimeCountsTowardParentWithoutHavingAGoal() throws {
        let ledger = try fixture()
        let goals = ledger.calculatedAllocationGoals(["guitar": 20, "rest": 10])
        var period = AllocationPeriod(); period.trackedMinutes = 100; period.representedDays = 1
        period.directMinutes = ["guitar": 15, "music": 5, "rest": 10, "life": 10, "teaching": 60]
        XCTAssertEqual(goals["music"], 20)
        XCTAssertEqual(period.total(for: "music", ledger: ledger), 20)
        XCTAssertEqual(period.total(for: "life", ledger: ledger), 40)
        XCTAssertEqual(ledger.children(of: nil).reduce(0) { $0 + period.total(for: $1.id, ledger: ledger) }, 100)
        XCTAssertEqual(AllocationGoalFeedback(actual: period.percent(period.total(for: "music", ledger: ledger)), goal: 20), .aligned)
        XCTAssertEqual(AllocationGoalFeedback(actual: period.percent(period.total(for: "guitar", ledger: ledger)), goal: 20), .below)
    }
    func testCopyBaselineLeavesDirectAndUncategorizedSharesUnallocated() throws {
        let ledger = try fixture()
        var period = AllocationPeriod(); period.trackedMinutes = 5; period.representedDays = 1
        period.directMinutes = ["teaching": 1, "guitar": 1, "music": 1, "life": 1, "uncategorized": 1]
        let goals = try XCTUnwrap(ledger.goalsFromAllocation(period))
        XCTAssertEqual(goals, ["work": 20, "teaching": 20, "life": 20, "music": 20, "guitar": 20, "rest": 0])
        XCTAssertEqual(ledger.allocationGoalBalance(goals).total, 40)
        XCTAssertEqual(ledger.goalPercentage(for: "guitar", from: period), 20)
        XCTAssertNil(ledger.goalPercentage(for: "music", from: period))
        XCTAssertNil(ledger.goalsFromAllocation(AllocationPeriod()))
    }
    func testLeafOnlyBaselineRoundsTo100EvenWithManySmallShares() throws {
        var ledger = try fixture()
        ledger.categories += (0..<17).map { LedgerCategory(id: "extra\($0)", name: "Extra \($0)") }
        var period = AllocationPeriod(); period.representedDays = 3
        let leaves = ledger.categories.filter { ledger.children(of: $0.id).isEmpty }
        for (index, category) in leaves.enumerated() { period.directMinutes[category.id] = Double(index + 1) / 7 }
        period.trackedMinutes = period.directMinutes.values.reduce(0, +)
        let goals = try XCTUnwrap(ledger.goalsFromAllocation(period))
        XCTAssertEqual(ledger.allocationGoalBalance(goals).total, 100, accuracy: 0.0000001)
        XCTAssertTrue(ledger.allocationGoalBalance(goals).isComplete)
    }
    func testCopiedGoalsRemainFixedWhenNewLogsArrive() throws {
        var ledger = try fixture()
        var period = AllocationPeriod(); period.trackedMinutes = 100; period.representedDays = 1
        period.directMinutes = ["teaching": 70, "guitar": 30]
        let goals = try XCTUnwrap(ledger.goalsFromAllocation(period))
        try ledger.saveAllocationGoals(goals, writer: "phone")
        try ledger.saveSample(at: Date().addingTimeInterval(-60), activity: "New activity", categoryIDs: ["music"], writer: "phone")
        XCTAssertEqual(ledger.currentGoals(), goals)
    }
    func testLegacyMigrationPreservesOriginalIndependentParentGoalsInHistory() throws {
        var ledger = try fixture()
        let earlier = Date().addingTimeInterval(-3600)
        try ledger.saveTargets(["work": 60, "life": 40], effectiveAt: earlier, writer: "old")
        let raw = try JSONEncoder().encode(ledger)
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("leafGoalPercentages"))
        ledger = try JSONDecoder().decode(Ledger.self, from: raw)
        let original = ledger.currentBudget()
        XCTAssertNil(ledger.currentGoals()["work"])
        try ledger.updateAllocationGoal(categoryID: "guitar", percentage: 15, writer: "phone")
        XCTAssertEqual(ledger.currentBudget(at: earlier), original)
        XCTAssertEqual(ledger.currentBudget(at: earlier)?.percentages, ["work": 60, "life": 40])
        XCTAssertEqual(ledger.currentGoals(), ["life": 15, "music": 15, "guitar": 15])
        XCTAssertEqual(ledger.targetBudgets?.count, 2)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(restored, ledger)
    }
    func testPreviousNestedBudgetPreservesLeafValuesAndRecalculatesParentsWithoutRewritingHistory() throws {
        var ledger = try fixture()
        ledger.targetBudgets = [TargetBudget(id: "previous", effectiveAt: Date().addingTimeInterval(-60), percentages: ["work": 70, "teaching": 30, "life": 30, "music": 25, "guitar": 10], revision: Revision(counter: 1, writer: "old"), topLevelCategoryIDs: ["work", "life"])]
        let original = ledger.targetBudgets
        XCTAssertEqual(ledger.currentGoals(), ["work": 30, "teaching": 30, "life": 10, "music": 10, "guitar": 10])
        XCTAssertEqual(ledger.targetBudgets, original)
        try ledger.updateAllocationGoal(categoryID: "rest", percentage: 20, writer: "phone")
        XCTAssertEqual(ledger.targetBudgets?.first, original?.first)
        XCTAssertEqual(ledger.currentGoals()["life"], 30)
    }
    func testFullCompanionAndPartialCloudPayloadsRetainLeafInputsAndCalculatedTotals() throws {
        var phone = try fixture()
        try phone.saveAllocationGoals(["teaching": 80, "guitar": 50, "rest": 25], writer: "phone")
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(phone))
        var watch = try fixture(); watch.merge(decoded)
        XCTAssertEqual(watch.currentGoals(), phone.currentGoals())
        XCTAssertEqual(watch.currentBudget()?.allocated, 155)
        XCTAssertEqual(watch.currentBudget()?.leafGoalPercentages, ["teaching": 80, "guitar": 50, "rest": 25])
        var cloud = Ledger(); cloud.categories = []; cloud.targetBudgets = phone.targetBudgets
        var receiver = try fixture(); receiver.merge(cloud)
        XCTAssertEqual(receiver.currentGoals(), phone.currentGoals())
        XCTAssertEqual(receiver.categories.count, phone.categories.count)
    }
    func testFinishingOneFieldPreservesLatestSyncedOtherLeafGoal() throws {
        var phone = try fixture()
        try phone.saveAllocationGoals(["teaching": 50, "rest": 50], writer: "phone")
        var other = phone
        try other.updateAllocationGoal(categoryID: "teaching", percentage: 60, writer: "other")
        phone.merge(other)
        try phone.updateAllocationGoal(categoryID: "guitar", percentage: 15, writer: "phone")
        XCTAssertEqual(phone.currentGoals(), ["work": 60, "teaching": 60, "life": 65, "music": 15, "guitar": 15, "rest": 50])
    }
    func testMovingAndUndoRecalculateBothBranchesAndKeepRawLogs() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["teaching": 50, "rest": 40, "guitar": 10], writer: "phone")
        try ledger.saveSample(at: Date().addingTimeInterval(-60), activity: "Guitar", categoryIDs: ["guitar"], writer: "phone")
        let goals = ledger.currentGoals(), samples = ledger.entries
        let undo = try ledger.groupCategories(["music"], under: "work", writer: "phone")
        XCTAssertEqual(ledger.currentGoals()["work"], 60)
        XCTAssertEqual(ledger.currentGoals()["life"], 40)
        XCTAssertEqual(ledger.currentGoals()["guitar"], 10)
        try ledger.undoCategoryMove(undo, writer: "phone")
        XCTAssertEqual(ledger.currentGoals(), goals)
        XCTAssertEqual(ledger.entries, samples)
        try ledger.deleteCategory(id: "music", writer: "phone")
        XCTAssertNil(ledger.currentGoals()["music"])
        XCTAssertEqual(ledger.currentGoals()["life"], 50)
        XCTAssertEqual(ledger.currentGoals()["guitar"], 10)
        XCTAssertEqual(ledger.categoryParents["guitar"], "life")
        XCTAssertEqual(ledger.entries, samples)
    }
    func testFormerParentDoesNotTurnItsOldTotalIntoAnotherLeafGoalAfterMoveOrRestore() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["teaching": 50, "guitar": 30, "rest": 20], writer: "phone")
        try ledger.groupCategories(["guitar"], under: "work", writer: "phone")
        XCTAssertNil(ledger.currentGoals()["music"])
        XCTAssertEqual(ledger.currentGoals()["work"], 80)
        XCTAssertEqual(ledger.currentBudget()?.allocated, 100)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertNil(restored.currentGoals()["music"])
        XCTAssertEqual(restored.currentBudget()?.allocated, 100)
    }
    func testAddingChildrenReplacesEditableParentWithCalculatedGoalAndUndoRestoresIt() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["teaching": 50, "guitar": 30, "rest": 20], writer: "phone")
        let undo = try ledger.groupCategories(["guitar"], under: "rest", writer: "phone")
        XCTAssertEqual(ledger.currentGoals()["rest"], 30)
        XCTAssertEqual(ledger.currentGoals()["life"], 30)
        XCTAssertEqual(ledger.currentBudget()?.allocated, 80)
        try ledger.undoCategoryMove(undo, writer: "phone")
        XCTAssertEqual(ledger.currentGoals()["rest"], 20)
        XCTAssertEqual(ledger.currentGoals()["music"], 30)
        XCTAssertEqual(ledger.currentBudget()?.allocated, 100)
    }
    func testFeedbackIsAlignmentRatherThanMaximization() {
        XCTAssertEqual(AllocationGoalFeedback(actual: 5.5, goal: 8), .below)
        XCTAssertEqual(AllocationGoalFeedback(actual: 8, goal: 8), .aligned)
        XCTAssertEqual(AllocationGoalFeedback(actual: 8.04, goal: 8), .aligned)
        XCTAssertEqual(AllocationGoalFeedback(actual: 12, goal: 8), .above)
    }
}
