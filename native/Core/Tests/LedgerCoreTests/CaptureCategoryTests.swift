import XCTest
@testable import LedgerCore

final class CaptureCategoryTests: XCTestCase {
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        try ledger.saveCategory(id: nil, name: "Teaching", writer: "phone")
        let child = try XCTUnwrap(ledger.categories.first { $0.name == "Teaching" })
        try ledger.moveCategory(child.id, to: "work", writer: "phone")
        for id in ["a", "b", "c"] { try ledger.addCapture(text: id, id: id, writer: "phone") }
        ledger.prepareRanking(writer: "phone")
        return ledger
    }

    func testCategorizingDuringReviewPreservesQuestionRankingNotesAndRawLogs() throws {
        var ledger = try fixture()
        let id = try XCTUnwrap(ledger.rankingPair).first
        try ledger.updateCapture(id: id, text: "Prepare class", notes: "Keep these notes", writer: "phone")
        let before = try XCTUnwrap(ledger.captures.first { $0.id == id }), ranking = ledger.inboxRanking, entries = ledger.entries
        try ledger.categorizeCapture(id: id, categoryIDs: ["work", "social", "work"], writer: "phone")
        ledger.normalizeInboxRanking(writer: "phone")
        let after = try XCTUnwrap(ledger.captures.first { $0.id == id })
        XCTAssertEqual(ledger.categoryIDs(for: after), ["social", "work"])
        XCTAssertEqual(after.createdAt, before.createdAt); XCTAssertEqual(after.notes, before.notes)
        XCTAssertEqual(after.reviewRevision, before.reviewRevision); XCTAssertEqual(ledger.inboxRanking, ranking)
        XCTAssertEqual(ledger.entries, entries); XCTAssertGreaterThan(after.revision, before.revision)
        let revision = after.revision
        try ledger.categorizeCapture(id: id, categoryIDs: ["social", "work"], writer: "phone")
        XCTAssertEqual(ledger.captures.first { $0.id == id }?.revision, revision)
    }

    func testSharedHierarchyValidationRenameAndDeletionKeepIdeaData() throws {
        var ledger = try fixture()
        let child = try XCTUnwrap(ledger.categories.first { $0.name == "Teaching" }).id
        XCTAssertThrowsError(try ledger.categorizeCapture(id: "a", categoryIDs: ["work", child], writer: "phone"))
        XCTAssertThrowsError(try ledger.categorizeCapture(id: "a", categoryIDs: ["missing"], writer: "phone"))
        try ledger.categorizeCapture(id: "a", categoryIDs: [child, "social"], writer: "phone")
        XCTAssertTrue(ledger.searchInbox("", categoryID: "work").contains { $0.id == "a" })
        try ledger.saveCategory(id: child, name: "Class preparation", writer: "phone")
        XCTAssertEqual(ledger.searchInbox("class preparation").map(\.id), ["a"])
        XCTAssertTrue(ledger.inboxExport.text.contains("Work › Class preparation"))
        let raw = ledger.captures.first { $0.id == "a" }
        try ledger.deleteCategory(id: child, writer: "phone")
        XCTAssertEqual(ledger.captures.first { $0.id == "a" }, raw)
        XCTAssertEqual(ledger.categoryIDs(for: raw!), ["social"])
        XCTAssertFalse(ledger.searchInbox("", categoryID: "work").contains { $0.id == "a" })
    }

    func testTextAndCategoryFiltersCombineAndPreserveGlobalRanks() throws {
        var ledger = try fixture()
        for id in ["a", "b", "c"] { try ledger.updateCapture(id: id, text: "Read \(id)", notes: "Project notes", writer: "phone") }
        ledger.inboxRanking?.ordered = ["c", "a", "b"]
        ledger.inboxRanking?.topTen?.candidate = nil
        try ledger.categorizeCapture(id: "a", categoryIDs: ["work"], writer: "phone")
        try ledger.categorizeCapture(id: "c", categoryIDs: ["work", "social"], writer: "phone")
        XCTAssertEqual(ledger.searchInbox("project", categoryID: "work").map(\.id), ["c", "a"])
        XCTAssertEqual(ledger.searchInbox("work").map(\.id), ["c", "a"])
        XCTAssertEqual(ledger.searchInbox("", categoryID: "uncategorized").map(\.id), ["b"])
        XCTAssertTrue(ledger.searchInbox("absent", categoryID: "work").isEmpty)
        ledger.setCaptureReference("a", reference: true, writer: "phone")
        XCTAssertTrue(ledger.searchInbox("", categoryID: "work").contains { $0.id == "a" })
        ledger.setCaptureDeleted("a", deleted: true, writer: "phone")
        XCTAssertFalse(ledger.searchInbox("", categoryID: "work").contains { $0.id == "a" })
    }

    func testLegacyCapturesBackupCloudAndCompanionPreserveLabelsAndRanking() throws {
        var phone = try fixture(), staleWatch = phone
        let legacy = try JSONEncoder().encode(phone)
        XCTAssertNil(try JSONDecoder().decode(Ledger.self, from: legacy).captures[0].categoryIDs)
        try phone.categorizeCapture(id: "a", categoryIDs: ["work"], writer: "phone")
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        XCTAssertEqual(restored, phone)
        staleWatch.merge(phone)
        XCTAssertEqual(staleWatch.captures.first { $0.id == "a" }?.categoryIDs, ["work"])
        phone.merge(staleWatch)
        XCTAssertEqual(phone.inboxRanking, restored.inboxRanking)
        var cloud = Ledger(); cloud.captures = [try XCTUnwrap(phone.captures.first { $0.id == "a" })]
        var receiver = Ledger(); receiver.merge(cloud)
        XCTAssertEqual(receiver.captures.first?.categoryIDs, ["work"])
        var delivery = CompanionQuickDelivery()
        let packet = try JSONDecoder().decode(CompanionQuickPacket.self, from: XCTUnwrap(delivery.prepare(phone, id: "categories")))
        receiver.merge(packet.ledger); receiver.merge(phone)
        XCTAssertEqual(receiver.captures.first { $0.id == "a" }?.categoryIDs, ["work"])
        XCTAssertTrue(phone.inboxExport.text.contains("Categories: Work"))
    }

    func testExpandingLegacyTenPreservesOrderAndDoesNotArbitrarilyPromoteBacklog() throws {
        var ledger = Ledger(), ranking = InboxRanking()
        for index in 0..<12 {
            let id = String(format: "%02d", index)
            try ledger.addCapture(text: id, id: id, writer: "old")
            if index < 10 { ranking.ordered.append(id) }
        }
        ranking.topTen = TopTenRanking(backlog: ["10", "11"])
        ledger.inboxRanking = ranking
        let old = ranking.ordered
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(InboxRanking.priorityLimit, 20)
        XCTAssertEqual(ledger.rankedCaptureIDs, old)
        XCTAssertEqual(Set(ledger.backlogCaptures.map(\.id)), ["10", "11"])
        XCTAssertNil(ledger.rankingPair)
        XCTAssertTrue(ledger.needsTopTenReplenishment)
        XCTAssertEqual(try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger.rankedCaptureIDs, old)
    }
}
