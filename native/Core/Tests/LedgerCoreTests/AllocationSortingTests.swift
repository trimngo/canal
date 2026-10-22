import XCTest
@testable import LedgerCore

final class AllocationSortingTests: XCTestCase {
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "music", name: "Music"),
            LedgerCategory(id: "teaching", name: "Teaching"), LedgerCategory(id: "admin", name: "Administration"),
            LedgerCategory(id: "blank", name: "Blank goal"), LedgerCategory(id: "zero", name: "Zero goal")]
        try ledger.moveCategory("teaching", to: "work", writer: "test")
        try ledger.moveCategory("admin", to: "work", writer: "test")
        return ledger
    }
    private let today = AllocationPeriod(trackedMinutes: 110, directMinutes: ["work": 20, "teaching": 30, "admin": 10, "music": 50], representedDays: 1)
    private let week = AllocationPeriod(trackedMinutes: 90, directMinutes: ["teaching": 10, "music": 80], representedDays: 3, requestedDays: 7)

    func testGoalSortKeepsZeroSeparateFromBlankInBothDirections() throws {
        let ledger = try fixture(), roots = ledger.children(of: nil), goals = ["work": 30.0, "music": 15, "zero": 0]
        XCTAssertEqual(ledger.sortedAllocationCategories(roots, by: .goal, descending: true, goals: goals, today: today, week: week).map(\.id), ["work", "music", "zero", "blank"])
        XCTAssertEqual(ledger.sortedAllocationCategories(roots, by: .goal, descending: false, goals: goals, today: today, week: week).map(\.id), ["zero", "music", "work", "blank"])
    }

    func testTodayAndWeekSortUseTheirOwnAggregatedParentTotals() throws {
        let ledger = try fixture(), roots = ledger.children(of: nil)
        XCTAssertEqual(ledger.sortedAllocationCategories(roots, by: .today, descending: true, goals: [:], today: today, week: week).map(\.id), ["work", "music", "blank", "zero"])
        XCTAssertEqual(ledger.sortedAllocationCategories(roots, by: .week, descending: true, goals: [:], today: today, week: week).map(\.id), ["music", "work", "blank", "zero"])
        XCTAssertEqual(ledger.sortedAllocationCategories(roots, by: .today, descending: false, goals: [:], today: today, week: week).map(\.id), ["blank", "zero", "music", "work"])
    }

    func testSiblingSortingPreservesHierarchyIdentitiesAndStoredOrder() throws {
        let ledger = try fixture(), before = ledger
        let sorted = ledger.sortedAllocationCategories(ledger.children(of: "work"), by: .today, descending: true, goals: [:], today: today, week: week)
        XCTAssertEqual(sorted.map(\.id), ["teaching", "admin"])
        XCTAssertTrue(sorted.allSatisfy { $0.parentID == "work" })
        XCTAssertEqual(ledger, before)
    }

    func testCategorySortUsesNaturalNamesAndStableIdentityTies() {
        var ledger = Ledger()
        ledger.categories = [LedgerCategory(id: "b", name: "Item 2"), LedgerCategory(id: "c", name: "Item 10"), LedgerCategory(id: "a", name: "Item 2")]
        XCTAssertEqual(ledger.sortedAllocationCategories(ledger.categories, by: .category, descending: false, goals: [:], today: today, week: week).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(ledger.sortedAllocationCategories(ledger.categories, by: .category, descending: true, goals: [:], today: today, week: week).map(\.id), ["c", "a", "b"])
    }

    func testMissingActualDataSortsDeterministicallyWithoutInventingValues() throws {
        let ledger = try fixture(), empty = AllocationPeriod()
        XCTAssertEqual(ledger.sortedAllocationCategories(ledger.children(of: nil), by: .week, descending: true, goals: [:], today: empty, week: empty).map(\.id), ["blank", "music", "work", "zero"])
    }
}
