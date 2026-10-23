import XCTest
@testable import LedgerCore

final class InboxCategoryOverviewTests: XCTestCase {
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"),
            LedgerCategory(id: "admin", name: "Admin"), LedgerCategory(id: "music", name: "Music")]
        try ledger.moveCategory("teaching", to: "work", writer: "test")
        try ledger.moveCategory("admin", to: "work", writer: "test")
        for (i, id) in ["a", "b", "done", "reference", "unseen", "deleted"].enumerated() {
            try ledger.addCapture(text: id, id: id, writer: "test", now: Date(timeIntervalSince1970: Double(100 + i)))
        }
        try ledger.categorizeCapture(id: "a", categoryIDs: ["teaching", "admin"], writer: "test")
        for id in ["b", "done", "deleted"] { try ledger.categorizeCapture(id: id, categoryIDs: ["work"], writer: "test") }
        try ledger.categorizeCapture(id: "reference", categoryIDs: ["music"], writer: "test")
        ledger.setCaptureDone(id: "done", done: true, writer: "test")
        ledger.setCaptureReference("reference", reference: true, writer: "test")
        ledger.setCaptureDeleted("deleted", deleted: true, writer: "test")
        return ledger
    }
    func testQueueIncludesEverySavedListAndUncategorizedOnlyIsAnIndependentSubset() throws {
        let ledger = try fixture()
        XCTAssertEqual(ledger.inboxCategorizationIDs(uncategorizedOnly: false), ["unseen", "reference", "done", "b", "a"])
        XCTAssertEqual(ledger.inboxCategorizationIDs(uncategorizedOnly: true), ["unseen"])
    }
    func testCountsDeduplicateSiblingAssignmentsAndPreserveOverallRank() throws {
        let ledger = try fixture(), ranked = [ledger.captures[1], ledger.captures[0]]
        let rows = ledger.inboxCategorySummaries(ranked: ranked)
        let work = try XCTUnwrap(rows.first { $0.id == "work" })
        XCTAssertEqual(work.count, 3); XCTAssertEqual(work.topRanked?.id, "b"); XCTAssertEqual(work.overallRank, 1)
        XCTAssertEqual(rows.first { $0.id == "teaching" }?.count, 1)
        XCTAssertEqual(rows.first { $0.id == "teaching" }?.overallRank, 2)
        XCTAssertEqual(rows.first { $0.id == "music" }?.count, 1)
        XCTAssertNil(rows.first { $0.id == "music" }?.topRanked)
        XCTAssertEqual(rows.first { $0.id == "uncategorized" }?.count, 1)
        XCTAssertEqual(ledger.searchInbox("", categoryID: "work", ranked: ranked).map(\.id), ["b", "a", "done"])
    }
    func testRenamingAndDeletingUsesTheSameCategoryIdentitiesAsLogs() throws {
        var ledger = try fixture()
        try ledger.saveCategory(id: "teaching", name: "Class preparation", writer: "test")
        XCTAssertEqual(ledger.inboxCategorySummaries(ranked: []).first { $0.id == "teaching" }?.name, "Class preparation")
        try ledger.deleteCategory(id: "work", writer: "test")
        XCTAssertFalse(ledger.inboxCategorySummaries(ranked: []).contains { $0.id == "work" })
        XCTAssertEqual(Set(ledger.inboxCategorizationIDs(uncategorizedOnly: true)), ["unseen", "done", "b"])
        XCTAssertEqual(ledger.captures.count, 6)
    }
    func testBulkCategorizationPreservesRankingProgressAndLogDataAndSurvivesBackup() throws {
        var ledger = try fixture(); ledger.prepareRanking(writer: "test")
        let before = ledger.inboxRanking, logs = ledger.entries, raw = ledger.captures
        let queue = ledger.inboxCategorizationIDs(uncategorizedOnly: false)
        for id in queue { try ledger.categorizeCapture(id: id, categoryIDs: ["music"], writer: "test") }
        ledger.normalizeInboxRanking(writer: "test")
        XCTAssertEqual(ledger.inboxRanking, before); XCTAssertEqual(ledger.entries, logs)
        XCTAssertEqual(ledger.captures.map(\.createdAt), raw.map(\.createdAt))
        XCTAssertEqual(ledger.captures.map(\.isDone), raw.map(\.isDone))
        XCTAssertEqual(ledger.captures.map(\.reviewRevision), raw.map(\.reviewRevision))
        XCTAssertTrue(ledger.inboxCategorizationIDs(uncategorizedOnly: true).isEmpty)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(restored, ledger)
        var peer = Ledger(); peer.merge(restored)
        XCTAssertEqual(peer.inboxCategorizationIDs(uncategorizedOnly: false), queue)
    }
    func testFrozenQueueDoesNotChangeWhenANewIdeaArrives() throws {
        var ledger = try fixture()
        let queue = ledger.inboxCategorizationIDs(uncategorizedOnly: true)
        try ledger.addCapture(text: "Arrived during categorization", id: "new", writer: "watch")
        XCTAssertEqual(queue, ["unseen"])
        XCTAssertEqual(ledger.inboxCategorizationIDs(uncategorizedOnly: true), ["new", "unseen"])
    }
}
