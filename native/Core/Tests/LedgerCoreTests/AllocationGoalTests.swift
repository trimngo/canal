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
    func testNestedGoalsCountWithinParentsAndDirectTimeHasRoom() throws {
        var ledger = try fixture()
        let goals = ["work": 50.0, "teaching": 30, "life": 50, "music": 20, "guitar": 10, "rest": 10]
        try ledger.saveAllocationGoals(goals, writer: "phone")
        XCTAssertEqual(ledger.currentGoals(), goals)
        XCTAssertEqual(ledger.currentBudget()?.allocated, 100)
        XCTAssertEqual(ledger.currentBudget()?.unallocated, 0)
        XCTAssertTrue(ledger.allocationGoalBalance(goals).isComplete)
        XCTAssertEqual(ledger.currentTargets(), ["work": 50, "life": 50])
    }
    func testIncompleteAndOverAllocatedEditsPersistWithoutRedistribution() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["work": 50, "life": 50, "music": 20], writer: "phone")
        try ledger.updateAllocationGoal(categoryID: "work", percentage: 60, writer: "phone")
        XCTAssertEqual(ledger.currentGoals(), ["work": 60, "life": 50, "music": 20])
        XCTAssertEqual(ledger.currentBudget()?.allocated, 110)
        XCTAssertFalse(ledger.allocationGoalBalance(ledger.currentGoals()).isComplete)
        try ledger.updateAllocationGoal(categoryID: "life", percentage: 40, writer: "phone")
        XCTAssertTrue(ledger.allocationGoalBalance(ledger.currentGoals()).isComplete)
        try ledger.updateAllocationGoal(categoryID: "music", percentage: nil, writer: "phone")
        XCTAssertNil(ledger.currentGoals()["music"])
        XCTAssertEqual(ledger.currentGoals()["work"], 60)
    }
    func testNestedOveragesAndMissingParentGoalsAreReportedWithoutDoubleCounting() throws {
        let ledger = try fixture()
        let goals = ["work": 50.0, "life": 50, "music": 30, "guitar": 20, "rest": 30]
        let status = ledger.allocationGoalBalance(goals)
        XCTAssertEqual(status.total, 100)
        XCTAssertEqual(status.overages, ["life": 10])
        XCTAssertFalse(status.isComplete)
        XCTAssertEqual(ledger.allocationGoalBalance(["work": 100, "guitar": 10]).missingRootGoals, ["life"])
        // Missing intermediate goals do not hide their children's allocation.
        XCTAssertEqual(ledger.allocationGoalBalance(["work": 50, "life": 50, "guitar": 40, "rest": 20]).overages, ["life": 10])
    }
    func testIndividualValidationIsAtomicAndSameValueDoesNotCreateHistory() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["work": 100], writer: "phone")
        let before = ledger
        try ledger.updateAllocationGoal(categoryID: "work", percentage: 100, writer: "phone")
        XCTAssertEqual(ledger, before)
        for value in [Double.nan, .infinity, -1, 101] {
            XCTAssertThrowsError(try ledger.updateAllocationGoal(categoryID: "music", percentage: value, writer: "phone"))
            XCTAssertEqual(ledger, before)
        }
        XCTAssertThrowsError(try ledger.updateAllocationGoal(categoryID: "missing", percentage: 5, writer: "phone"))
    }
    func testCopyBaselineRoundsOnceAndPreservesHierarchyAndUncategorizedShare() throws {
        let ledger = try fixture()
        var period = AllocationPeriod(); period.trackedMinutes = 3; period.representedDays = 1
        period.directMinutes = ["teaching": 1, "guitar": 1, "uncategorized": 1]
        let goals = try XCTUnwrap(ledger.goalsFromAllocation(period))
        XCTAssertEqual(goals["music"], goals["guitar"])
        XCTAssertEqual(goals["life"], goals["music"])
        XCTAssertNil(goals["uncategorized"])
        XCTAssertEqual(ledger.allocationGoalBalance(goals).total, 66.67, accuracy: 0.001)
        XCTAssertTrue(ledger.allocationGoalBalance(goals).overages.isEmpty)
        XCTAssertEqual(ledger.goalPercentage(for: "music", from: period), 33.33)
        XCTAssertNil(ledger.goalsFromAllocation(AllocationPeriod()))
    }
    func testFullyCategorizedBaselineAlwaysTotals100EvenWithManySmallShares() throws {
        var ledger = try fixture()
        ledger.categories += (0..<17).map { LedgerCategory(id: "extra\($0)", name: "Extra \($0)") }
        var period = AllocationPeriod(); period.representedDays = 3
        for (index, category) in ledger.categories.enumerated() {
            period.directMinutes[category.id] = Double(index + 1) / 7
        }
        period.trackedMinutes = period.directMinutes.values.reduce(0, +)
        let goals = try XCTUnwrap(ledger.goalsFromAllocation(period))
        XCTAssertEqual(ledger.allocationGoalBalance(goals).total, 100, accuracy: 0.0000001)
        XCTAssertTrue(ledger.allocationGoalBalance(goals).isComplete)
    }
    func testCopiedGoalsRemainFixedWhenNewLogsArrive() throws {
        var ledger = try fixture()
        var period = AllocationPeriod(); period.trackedMinutes = 100; period.representedDays = 1
        period.directMinutes = ["teaching": 70, "music": 30]
        let goals = try XCTUnwrap(ledger.goalsFromAllocation(period))
        try ledger.saveAllocationGoals(goals, writer: "phone")
        try ledger.saveSample(at: Date().addingTimeInterval(-60), activity: "New activity", categoryIDs: ["music"], writer: "phone")
        XCTAssertEqual(ledger.currentGoals(), goals)
    }
    func testLegacyMigrationHistoricalIntentAndBackupRoundTrip() throws {
        var ledger = try fixture()
        let earlier = Date().addingTimeInterval(-3600)
        try ledger.saveTargets(["work": 60, "life": 40], effectiveAt: earlier, writer: "old")
        let raw = try JSONEncoder().encode(ledger)
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("topLevelCategoryIDs"))
        ledger = try JSONDecoder().decode(Ledger.self, from: raw)
        try ledger.updateAllocationGoal(categoryID: "music", percentage: 15, writer: "phone")
        XCTAssertEqual(ledger.currentBudget(at: earlier)?.percentages, ["work": 60, "life": 40])
        XCTAssertEqual(ledger.currentGoals(), ["work": 60, "life": 40, "music": 15])
        XCTAssertEqual(ledger.targetBudgets?.count, 2)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(restored, ledger)
        XCTAssertEqual(restored.currentBudget()?.allocated, 100)
    }
    func testFullCompanionAndPartialCloudPayloadsRetainIncompleteNestedGoals() throws {
        var phone = try fixture()
        try phone.saveAllocationGoals(["work": 80, "life": 50, "music": 25], writer: "phone")
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(phone))
        var watch = try fixture(); watch.merge(decoded)
        XCTAssertEqual(watch.currentGoals(), phone.currentGoals())
        XCTAssertEqual(watch.currentBudget()?.allocated, 130)
        var cloud = Ledger(); cloud.categories = []; cloud.targetBudgets = phone.targetBudgets
        var receiver = try fixture(); receiver.merge(cloud)
        XCTAssertEqual(receiver.currentGoals(), phone.currentGoals())
        XCTAssertEqual(receiver.categories.count, phone.categories.count)
    }
    func testFinishingOneFieldPreservesLatestSyncedOtherGoal() throws {
        var phone = try fixture()
        try phone.saveAllocationGoals(["work": 50, "life": 50], writer: "phone")
        var other = phone
        try other.updateAllocationGoal(categoryID: "work", percentage: 60, writer: "other")
        phone.merge(other)
        try phone.updateAllocationGoal(categoryID: "music", percentage: 15, writer: "phone")
        XCTAssertEqual(phone.currentGoals(), ["work": 60, "life": 50, "music": 15])
    }
    func testMovingAndUndoKeepGoalIdentitiesAndDeletionKeepsRawLogs() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["work": 50, "life": 50, "music": 20, "guitar": 10], writer: "phone")
        try ledger.saveSample(at: Date().addingTimeInterval(-60), activity: "Guitar", categoryIDs: ["guitar"], writer: "phone")
        let goals = ledger.currentGoals(), samples = ledger.entries
        let undo = try ledger.groupCategories(["music"], under: "work", writer: "phone")
        XCTAssertEqual(ledger.currentGoals(), goals)
        try ledger.undoCategoryMove(undo, writer: "phone")
        XCTAssertEqual(ledger.currentGoals(), goals)
        XCTAssertEqual(ledger.categoryParents["music"], "life")
        XCTAssertEqual(ledger.entries, samples)
        try ledger.deleteCategory(id: "music", writer: "phone")
        XCTAssertNil(ledger.currentGoals()["music"])
        XCTAssertEqual(ledger.currentGoals()["guitar"], 10)
        XCTAssertEqual(ledger.categoryParents["guitar"], "life")
        XCTAssertEqual(ledger.entries, samples)
    }
    func testFeedbackIsAlignmentRatherThanMaximization() {
        XCTAssertEqual(AllocationGoalFeedback(actual: 5.5, goal: 8), .below)
        XCTAssertEqual(AllocationGoalFeedback(actual: 8, goal: 8), .aligned)
        XCTAssertEqual(AllocationGoalFeedback(actual: 8.04, goal: 8), .aligned)
        XCTAssertEqual(AllocationGoalFeedback(actual: 12, goal: 8), .above)
    }
}
