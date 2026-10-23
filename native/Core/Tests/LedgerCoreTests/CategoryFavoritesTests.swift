import XCTest
@testable import LedgerCore

final class CategoryFavoritesTests: XCTestCase {
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"),
            LedgerCategory(id: "admin", name: "Admin"), LedgerCategory(id: "music", name: "Music")]
        try ledger.moveCategory("teaching", to: "work", writer: "test")
        try ledger.moveCategory("admin", to: "work", writer: "test")
        try ledger.saveAllocationGoals(["teaching": 20, "admin": 0, "music": 10], effectiveAt: Date(timeIntervalSince1970: 0), writer: "test")
        return ledger
    }
    func testLegacyDataStartsWithoutFavoritesAndNoGoalsAreDiscarded() throws {
        let ledger = try fixture()
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertTrue(restored.favoriteCategoryIDs.isEmpty)
        XCTAssertEqual(restored.currentGoals(), ledger.currentGoals())
        XCTAssertTrue(restored.categories.allSatisfy { $0.isFavorite == nil })
    }
    func testParentAndMultipleSelectionFavoriteLeavesOnlyWithoutChangingTargets() throws {
        var ledger = try fixture()
        let budgets = ledger.targetBudgets, goals = ledger.currentGoals()
        try ledger.setCategoryFavorites(["work", "music", "teaching"], favorite: true, writer: "phone")
        XCTAssertEqual(ledger.favoriteCategoryIDs, ["teaching", "admin", "music"])
        XCTAssertEqual(ledger.currentGoals(), goals); XCTAssertEqual(ledger.targetBudgets, budgets)
        try ledger.setCategoryFavorites(["teaching"], favorite: false, writer: "phone")
        XCTAssertEqual(ledger.favoriteCategoryIDs, ["admin", "music"])
        try ledger.setCategoryFavorites(["work", "music"], favorite: false, writer: "phone")
        XCTAssertTrue(ledger.favoriteCategoryIDs.isEmpty)
    }
    func testDashboardTotalsCoverOnlyFavoritesAndKeepWholeDayWindow() throws {
        var ledger = try fixture(); ledger.settings.reportingTimeZoneIdentifier = "UTC"
        let now = ISO8601DateFormatter().date(from: "2026-10-23T12:00:00Z")!
        try ledger.setCategoryFavorites(["music"], favorite: true, writer: "phone")
        let all = try XCTUnwrap(ledger.dailyGoals(now: now))
        let visible = try XCTUnwrap(ledger.dailyGoals(now: now, favoritesOnly: true))
        XCTAssertEqual(visible.commitments.map(\.id), ["music"])
        XCTAssertEqual(visible.neededMinutes, 90)
        XCTAssertEqual(visible.window, all.window)
        XCTAssertEqual(visible.commitments[0].targetMinutes, all.commitments.first { $0.id == "music" }?.targetMinutes)
        XCTAssertEqual(visible.dayBarSegments.reduce(0) { $0 + $1.minutes }, visible.window.minutes)
        try ledger.setCategoryFavorites(["music"], favorite: false, writer: "phone")
        XCTAssertTrue(try XCTUnwrap(ledger.dailyGoals(now: now, favoritesOnly: true)).commitments.isEmpty)
    }
    func testFavoritePersistsAcrossRenameMoveBackupAndStaleDeviceMerge() throws {
        var phone = try fixture(), watch = phone
        try phone.setCategoryFavorites(["music"], favorite: true, writer: "phone")
        try phone.saveCategory(id: "music", name: "Playing music", writer: "phone")
        try phone.moveCategory("music", to: "work", writer: "phone")
        phone.merge(watch); watch.merge(phone)
        XCTAssertEqual(watch.favoriteCategoryIDs, ["music"])
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        XCTAssertEqual(restored.favoriteCategoryIDs, ["music"])
        XCTAssertEqual(restored.categories, phone.categories)
        try phone.setCategoryFavorites(["music"], favorite: false, writer: "phone")
        watch.merge(phone); XCTAssertTrue(watch.favoriteCategoryIDs.isEmpty)
    }
    func testInvalidSelectionIsAtomicAndRepeatedFavoriteDoesNotWrite() throws {
        var ledger = try fixture(); let original = ledger
        XCTAssertThrowsError(try ledger.setCategoryFavorites(["music", "missing"], favorite: true, writer: "phone"))
        XCTAssertEqual(ledger, original)
        try ledger.setCategoryFavorites(["music"], favorite: true, writer: "phone")
        let once = ledger
        try ledger.setCategoryFavorites(["music"], favorite: true, writer: "phone")
        XCTAssertEqual(ledger, once)
    }
}
