import XCTest
@testable import LedgerCore

final class InboxReferenceTests: XCTestCase {
    private func ranked() throws -> Ledger {
        var ledger = Ledger(), ranking = InboxRanking()
        for index in 1...12 {
            let id = "task-\(index)"
            try ledger.addCapture(text: id, id: id, writer: "phone")
            ranking.ordered.append(id)
        }
        ranking.revision = ledger.nextRevision(writer: "phone")
        ledger.inboxRanking = ranking
        ledger.normalizeInboxRanking(writer: "phone")
        return ledger
    }

    func testReferenceHasItsOwnListAndDoesNotRankOrReplenish() throws {
        var ledger = try ranked()
        let before = try XCTUnwrap(ledger.captures.first { $0.id == "task-3" })
        try ledger.updateCapture(id: before.id, text: before.text, notes: "Useful reference\nNo next action", writer: "phone")
        ledger.setCaptureReference(before.id, reference: true, writer: "phone")
        XCTAssertEqual(ledger.referenceCaptures.map(\.id), [before.id])
        XCTAssertEqual(ledger.rankedCaptureIDs, (1...10).filter { $0 != 3 }.map { "task-\($0)" })
        XCTAssertFalse(ledger.activeCaptures.contains { $0.id == before.id })
        XCTAssertFalse(ledger.backlogCaptures.contains { $0.id == before.id })
        XCTAssertFalse(ledger.unseenCaptures.contains { $0.id == before.id })
        let saved = try XCTUnwrap(ledger.captures.first { $0.id == before.id })
        XCTAssertEqual(saved.createdAt, before.createdAt)
        XCTAssertEqual(saved.notes, "Useful reference\nNo next action")
        XCTAssertEqual(ledger.captures.count, 12)
        ledger.replenishTopTen(writer: "phone")
        while let pair = ledger.rankingPair {
            XCTAssertNotEqual(pair.first, before.id); XCTAssertNotEqual(pair.second, before.id)
            ledger.chooseCapture(pair.first, from: pair, writer: "phone")
        }
        XCTAssertEqual(ledger.rankedCaptureIDs.count, 10)
    }

    func testMovingReferenceBackRequiresFreshReviewWithoutReorderingOtherIdeas() throws {
        var ledger = try ranked()
        ledger.setCaptureReference("task-1", reference: true, writer: "phone")
        let others = ledger.rankedCaptureIDs
        ledger.setCaptureReference("task-1", reference: false, writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs, others)
        XCTAssertTrue(ledger.referenceCaptures.isEmpty)
        XCTAssertEqual(ledger.unseenCaptures.map(\.id), ["task-1"])
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "task-1")
        XCTAssertNotNil(ledger.rankingPair) // Previous comparisons cannot silently place it.
    }

    func testMovingCurrentComparisonItemToReferencePreservesRestAndRejectsStaleChoice() throws {
        var ledger = try ranked()
        try ledger.addCapture(text: "New candidate", id: "new", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        let pair = try XCTUnwrap(ledger.rankingPair)
        XCTAssertEqual(pair.first, "new")
        ledger.setCaptureReference("new", reference: true, writer: "phone")
        let saved = ledger
        ledger.chooseCapture(pair.first, from: pair, writer: "phone")
        XCTAssertEqual(ledger, saved)
        XCTAssertEqual(ledger.rankedCaptureIDs, (1...10).map { "task-\($0)" })
        XCTAssertEqual(ledger.referenceCaptures.map(\.id), ["new"])
    }

    func testEditingWhileRankingKeepsThePairAndAllOtherAnswers() throws {
        var ledger = try ranked()
        try ledger.addCapture(text: "New candidate", id: "new", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        let pair = try XCTUnwrap(ledger.rankingPair), ranking = ledger.inboxRanking
        try ledger.updateCapture(id: "new", text: "Updated candidate", notes: "Progress", writer: "phone")
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair, pair)
        XCTAssertEqual(ledger.inboxRanking, ranking)
        ledger.chooseCapture(pair.first, from: pair, writer: "phone")
        XCTAssertEqual(ledger.inboxRanking?.topTen?.candidate?.item, "new")
    }

    func testReferenceCancelsSnoozeAndCannotBeSnoozedOrRankedUntilMovedBack() throws {
        var ledger = try ranked()
        ledger.snoozeCapture("task-1", until: Date().addingTimeInterval(86400), writer: "phone")
        ledger.setCaptureReference("task-1", reference: true, writer: "phone")
        XCTAssertTrue(ledger.snoozedCaptures.isEmpty)
        XCTAssertNil(ledger.captures.first { $0.id == "task-1" }?.snoozedUntil)
        let saved = ledger
        ledger.snoozeCapture("task-1", until: Date().addingTimeInterval(86400), writer: "phone")
        ledger.rerankCapture("task-1", writer: "phone")
        ledger.bringBackCapture("task-1", writer: "phone")
        XCTAssertEqual(ledger, saved)
    }

    func testReferenceDeletionCompletionRestoreAndBackupKeepOriginalTask() throws {
        var ledger = try ranked()
        ledger.setCaptureReference("task-1", reference: true, writer: "phone")
        ledger.setCaptureDeleted("task-1", deleted: true, writer: "phone")
        XCTAssertTrue(ledger.referenceCaptures.isEmpty)
        ledger.setCaptureDeleted("task-1", deleted: false, writer: "phone")
        XCTAssertEqual(ledger.referenceCaptures.map(\.id), ["task-1"])
        ledger.setCaptureDone(id: "task-1", done: true, writer: "phone")
        XCTAssertTrue(ledger.referenceCaptures.isEmpty)
        ledger.setCaptureDone(id: "task-1", done: false, writer: "phone")
        XCTAssertEqual(ledger.referenceCaptures.map(\.id), ["task-1"])
        XCTAssertEqual(try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger, ledger)
    }

    func testReferenceNotesAndRankingSurviveCompanionAndCloudStyleRoundTrips() throws {
        var phone = try ranked(), watch = phone
        try phone.updateCapture(id: "task-1", text: "Reference title", notes: "Reference notes", writer: "phone")
        phone.setCaptureReference("task-1", reference: true, writer: "phone")
        var quick = CompanionQuickDelivery()
        let data = try XCTUnwrap(quick.prepare(phone, id: "reference"))
        watch.merge(try JSONDecoder().decode(CompanionQuickPacket.self, from: data).ledger)
        watch.normalizeInboxRanking(writer: "watch")
        XCTAssertEqual(watch.referenceCaptures, phone.referenceCaptures)
        let snapshot = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(phone))
        watch.merge(snapshot); watch.normalizeInboxRanking(writer: "watch")
        XCTAssertEqual(watch.referenceCaptures, phone.referenceCaptures)
        watch.setCaptureReference("task-1", reference: false, writer: "watch")
        phone.merge(watch); phone.normalizeInboxRanking(writer: "phone")
        XCTAssertTrue(phone.referenceCaptures.isEmpty)
        XCTAssertTrue(phone.unseenCaptures.contains { $0.id == "task-1" })
        XCTAssertEqual(phone.captures.first { $0.id == "task-1" }?.notes, "Reference notes")
        let old = Capture(text: "Legacy", revision: Revision())
        XCTAssertNil(try JSONDecoder().decode(Capture.self, from: JSONEncoder().encode(old)).isReference)
    }

    func testClipboardExportNamesEveryListAndDistinguishesEvaluatedFromUnseen() throws {
        var ledger = try ranked()
        for id in ["reference", "snoozed", "partial", "unseen", "done", "deleted"] {
            try ledger.addCapture(text: "Title \(id)", id: id, writer: "phone")
        }
        ledger.setCaptureReference("reference", reference: true, writer: "phone")
        try ledger.updateCapture(id: "reference", text: "Title reference", notes: "Full\nReference notes", writer: "phone")
        ledger.snoozeCapture("snoozed", until: Date().addingTimeInterval(86400), writer: "phone")
        ledger.setCaptureDone(id: "done", done: true, writer: "phone")
        ledger.setCaptureDeleted("deleted", deleted: true, writer: "phone")
        ledger.rerankCapture("partial", writer: "phone")
        ledger.markRankingPresented(writer: "phone")
        let export = ledger.inboxExport
        func block(_ title: String) throws -> String {
            try XCTUnwrap(export.text.components(separatedBy: "\n\n").first { $0.contains(title) })
        }
        XCTAssertTrue(try block("Title reference").contains("List: Reference\n   Rank: Not ranked"))
        XCTAssertTrue(try block("Title reference").contains("Notes: Full\n   Reference notes"))
        XCTAssertTrue(try block("Title snoozed").contains("List: Snoozed\n   Rank: Not ranked"))
        XCTAssertTrue(try block("Title snoozed").contains("Snoozed until:"))
        XCTAssertTrue(try block("Title partial").contains("List: In progress\n   Rank: Placement incomplete"))
        XCTAssertTrue(try block("Title unseen").contains("List: New Ideas\n   Rank: Not evaluated"))
        XCTAssertTrue(try block("Title done").contains("List: Completed\n   Rank: Not ranked"))
        XCTAssertTrue(try block(". task-1\n").contains("List: Top 10 Priorities\n   Rank: 1"))
        XCTAssertTrue(try block(". task-11\n").contains("List: Backlog\n   Rank: Evaluated, outside Top 10"))
        XCTAssertFalse(export.text.contains("Title deleted"))
        XCTAssertEqual(export.count, 17)
    }
}
