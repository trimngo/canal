import XCTest
@testable import LedgerCore

final class AllocationCategoryIndexTests: XCTestCase {
    private func fixture() -> Ledger {
        var ledger = Ledger()
        ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "music", name: "Music"),
            LedgerCategory(id: "teaching", name: "Teaching"), LedgerCategory(id: "admin", name: "Administration"),
            LedgerCategory(id: "lesson", name: "Lessons"), LedgerCategory(id: "blank", name: "Blank"), LedgerCategory(id: "zero", name: "Zero")]
        for (id, parent) in [("teaching", "work"), ("admin", "work"), ("lesson", "teaching")] {
            let i = ledger.categories.firstIndex { $0.id == id }!
            ledger.categories[i].parentID = parent
        }
        return ledger
    }

    func testCachedHierarchyMatchesReconciledOutlineIncludingInvalidLinks() {
        var ledger = fixture()
        // Concurrent moves can create cycles or missing parents in synced data.
        ledger.categories[0].parentID = "lesson"
        ledger.categories[1].parentID = "missing"
        let index = AllocationCategoryIndex(ledger: ledger)
        for parent in [nil] + ledger.categories.map({ Optional($0.id) }) {
            XCTAssertEqual(index.children(of: parent), ledger.children(of: parent))
        }
        XCTAssertEqual(index.leafIDs, Set(ledger.categories.filter { ledger.children(of: $0.id).isEmpty }.map(\.id)))
    }

    func testPreparedTotalsMatchExistingAccountingWithoutDoubleCounting() {
        let ledger = fixture(), index = AllocationCategoryIndex(ledger: ledger)
        let period = AllocationPeriod(trackedMinutes: 100, directMinutes: ["work": 10, "teaching": 20, "lesson": 15, "admin": 5, "music": 25, "uncategorized": 25], representedDays: 1)
        let totals = index.totals(period.directMinutes)
        for category in ledger.categories { XCTAssertEqual(totals[category.id, default: 0], period.total(for: category.id, ledger: ledger)) }
        XCTAssertEqual(totals["work"], 50)
        XCTAssertEqual(totals["teaching"], 35)
        XCTAssertNil(totals["uncategorized"])
        XCTAssertEqual(index.children(of: nil).reduce(0) { $0 + totals[$1.id, default: 0] }, 75)
    }

    func testDraftGoalsKeepZeroBlankAndCalculatedParentsDistinct() {
        let ledger = fixture(), index = AllocationCategoryIndex(ledger: ledger)
        let draft = ["lesson": 12.5, "admin": 5, "zero": 0, "work": 99, "missing": 7]
        XCTAssertEqual(index.goals(draft), ledger.calculatedAllocationGoals(draft))
        XCTAssertEqual(index.goals(draft)["work"], 17.5)
        XCTAssertEqual(index.goals(draft)["zero"], 0)
        XCTAssertNil(index.goals(draft)["blank"])
        var edited = draft; edited["lesson"] = 20
        XCTAssertEqual(index.goals(edited)["work"], 25)
        XCTAssertEqual(index.goals(edited)["admin"], 5)
    }

    func testRebuildingAfterMoveChangesTotalsWithoutChangingTheEarlierSnapshot() {
        var ledger = fixture()
        let before = AllocationCategoryIndex(ledger: ledger)
        let minutes = ["lesson": 30.0]
        ledger.categories[2].parentID = "music"
        let after = AllocationCategoryIndex(ledger: ledger)
        XCTAssertEqual(before.totals(minutes)["work"], 30)
        XCTAssertNil(after.totals(minutes)["work"])
        XCTAssertEqual(after.totals(minutes)["music"], 30)
        XCTAssertEqual(before.totals(minutes)["work"], 30)
    }

    func testPreparedSortingMatchesExistingEveryColumnAndDirection() {
        let ledger = fixture(), index = AllocationCategoryIndex(ledger: ledger)
        let today = AllocationPeriod(trackedMinutes: 100, directMinutes: ["lesson": 30, "music": 60, "work": 10], representedDays: 1)
        let week = AllocationPeriod(trackedMinutes: 100, directMinutes: ["admin": 90, "zero": 10], representedDays: 2)
        let goals = index.goals(["lesson": 20, "music": 15, "zero": 0])
        for period in [today, AllocationPeriod()] {
            for column in AllocationSortColumn.allCases {
                for descending in [false, true] {
                    for parent in [nil, "work", "teaching"] {
                        let children = index.children(of: parent)
                        XCTAssertEqual(index.sorted(children, by: column, descending: descending, goals: goals,
                            todayTotals: period.sufficient ? index.totals(period.directMinutes) : nil, weekTotals: index.totals(week.directMinutes)),
                            ledger.sortedAllocationCategories(children, by: column, descending: descending, goals: goals, today: period, week: week))
                    }
                }
            }
        }
    }
}
