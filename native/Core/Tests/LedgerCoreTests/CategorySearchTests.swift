import XCTest
@testable import LedgerCore

final class CategorySearchTests: XCTestCase {
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"),
                             LedgerCategory(id: "music", name: "Music"), LedgerCategory(id: "guitar", name: "Guitar"),
                             LedgerCategory(id: "cafe", name: "Café"), LedgerCategory(id: "personal", name: "Personal")]
        try ledger.moveCategory("teaching", to: "work", writer: "test")
        try ledger.moveCategory("music", to: "work", writer: "test")
        try ledger.moveCategory("guitar", to: "music", writer: "test")
        return ledger
    }

    func testBlankSearchPreservesFullHierarchyOrderAndDoesNotMutateCategories() throws {
        let ledger = try fixture(), original = ledger
        XCTAssertEqual(ledger.searchCategories(" \n "), ledger.orderedCategories)
        XCTAssertEqual(ledger, original)
        XCTAssertTrue(ledger.searchCategories("not a category").isEmpty)
    }

    func testChildSearchKeepsAncestorContextAndExcludesUnrelatedSiblings() throws {
        let ledger = try fixture()
        XCTAssertEqual(ledger.searchCategories("guitar").map(\.id), ["work", "music", "guitar"])
        XCTAssertEqual(ledger.searchCategories("WORK guitar").map(\.id), ["work", "music", "guitar"])
        XCTAssertEqual(ledger.searchCategories("teaching").map(\.id), ["work", "teaching"])
    }

    func testParentSearchShowsItsBranchAndNamesIgnoreCaseAndAccents() throws {
        let ledger = try fixture()
        XCTAssertEqual(ledger.searchCategories(" MUSIC ").map(\.id), ["work", "music", "guitar"])
        XCTAssertEqual(ledger.searchCategories("work").map(\.id), ["work", "teaching", "music", "guitar"])
        XCTAssertEqual(ledger.searchCategories("CAFE").map(\.id), ["cafe"])
    }
}
