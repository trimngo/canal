import XCTest
@testable import LedgerCore

final class InboxSnoozeTests: XCTestCase {
    private func ranked() throws -> Ledger {
        var ledger = Ledger()
        for id in ["a", "b", "c"] {
            try ledger.addCapture(text: id, id: id, writer: "phone", now: Date(timeIntervalSince1970: 100))
        }
        ledger.prepareRanking(writer: "phone")
        while let pair = ledger.rankingPair {
            ledger.chooseCapture(min(pair.first, pair.second), from: pair, writer: "phone")
        }
        return ledger
    }

    func testSnoozeHidesRankedTaskAndKeepsIdentityCreationAndNotes() throws {
        var ledger = try ranked()
        try ledger.updateCapture(id: "a", text: "a", notes: "Called client\nNext: send proposal", writer: "phone")
        let original = try XCTUnwrap(ledger.captures.first { $0.id == "a" })
        let now = Date(), due = now.addingTimeInterval(7 * 86400)
        ledger.snoozeCapture("a", until: due, writer: "phone", now: now)
        XCTAssertEqual(ledger.rankedCaptureIDs, ["b", "c"])
        XCTAssertFalse(ledger.activeCaptures.contains { $0.id == "a" })
        XCTAssertFalse(ledger.backlogCaptures.contains { $0.id == "a" })
        XCTAssertFalse(ledger.unseenCaptures.contains { $0.id == "a" })
        XCTAssertEqual(ledger.snoozedCaptures.map(\.id), ["a"])
        XCTAssertEqual(ledger.captures.first { $0.id == "a" }?.createdAt, original.createdAt)
        XCTAssertEqual(ledger.captures.first { $0.id == "a" }?.notes, original.notes)
        XCTAssertEqual(ledger.captures.count, 3)
    }

    func testDueDateIsComputedWithoutTimerAndDoesNotChangeRawTask() throws {
        var ledger = try ranked()
        let now = Date(), due = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
        ledger.snoozeCapture("a", until: due, writer: "phone", now: now)
        let saved = ledger
        XCTAssertEqual(ledger.snoozedCaptures(at: due.addingTimeInterval(-1)).map(\.id), ["a"])
        XCTAssertTrue(ledger.snoozedCaptures(at: due).isEmpty)
        XCTAssertTrue(ledger.activeCaptures(at: due).contains { $0.id == "a" })
        XCTAssertEqual(ledger, saved)
    }

    func testOverdueIdeaReturnsAheadOfNewIdeasWithFreshComparisons() throws {
        var ledger = try ranked()
        // A past simulated snooze lets the normal Date-based projection see it due.
        let now = Date()
        ledger.snoozeCapture("a", until: now.addingTimeInterval(-1), writer: "phone", now: now.addingTimeInterval(-86400))
        try ledger.addCapture(text: "Brand new", id: "new", writer: "watch", now: now)
        XCTAssertEqual(ledger.unseenCaptures.map(\.id), ["a", "new"])
        XCTAssertTrue(ledger.partiallyRankedCaptures.isEmpty)
        XCTAssertEqual(ledger.rankedCaptureIDs, ["b", "c"])
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "a")
        XCTAssertNotNil(ledger.rankingPair) // Old a > b > c answers must not auto-place it.
    }

    func testBringBackNowPreservesCurrentPairThenReviewsReturnedIdeaFirst() throws {
        var ledger = try ranked()
        ledger.snoozeCapture("a", until: Date().addingTimeInterval(86400), writer: "phone")
        try ledger.addCapture(text: "new", id: "new", writer: "phone")
        try ledger.addCapture(text: "current", id: "current", writer: "phone", now: Date().addingTimeInterval(1))
        ledger.prepareRanking(writer: "phone")
        let old = try XCTUnwrap(ledger.rankingPair)
        XCTAssertEqual(old.first, "current")
        ledger.bringBackCapture("a", writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, old.first)
        XCTAssertEqual(ledger.rankingPair?.second, old.second)
        XCTAssertTrue(ledger.snoozedCaptures.isEmpty)
        var count = 0
        while let pair = ledger.rankingPair, pair.first == "current" {
            ledger.chooseCapture(pair.first, from: pair, writer: "phone")
            count += 1; XCTAssertLessThan(count, 10)
        }
        XCTAssertEqual(ledger.rankingPair?.first, "a")
        XCTAssertTrue(ledger.unseenCaptures.contains { $0.id == "new" })
    }

    func testSnoozingCurrentCandidateSafelyAdvancesAndRejectsOldAnswer() throws {
        var ledger = try ranked()
        try ledger.addCapture(text: "candidate", id: "candidate", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        let old = try XCTUnwrap(ledger.rankingPair)
        ledger.snoozeCapture("candidate", until: Date().addingTimeInterval(86400), writer: "phone")
        let before = ledger
        ledger.chooseCapture(old.first, from: old, writer: "phone")
        XCTAssertEqual(ledger, before)
        XCTAssertNil(ledger.rankingPair)
        XCTAssertEqual(ledger.rankedCaptureIDs, ["a", "b", "c"])
    }

    func testBackupCompanionAndCloudStyleMergesKeepNotesSnoozeAndFreshReview() throws {
        var phone = try ranked()
        var stale = phone
        try phone.updateCapture(id: "a", text: "a", notes: "Progress\nTwo steps done", writer: "phone")
        phone.snoozeCapture("a", until: Date().addingTimeInterval(86400), writer: "phone")
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        XCTAssertEqual(restored, phone)
        var quick = CompanionQuickDelivery()
        let data = try XCTUnwrap(quick.prepare(phone, id: "notes"))
        let packet = try JSONDecoder().decode(CompanionQuickPacket.self, from: data)
        var watch = Ledger(); watch.merge(packet.ledger); watch.normalizeInboxRanking(writer: "watch")
        XCTAssertEqual(watch.captures.first { $0.id == "a" }, phone.captures.first { $0.id == "a" })
        watch.merge(restored); watch.normalizeInboxRanking(writer: "watch")
        XCTAssertEqual(watch.rankedCaptureIDs, ["b", "c"])
        // Model a newer ranking record arriving separately from the capture,
        // as CloudKit may deliver records in either order.
        stale.inboxRanking?.revision = Revision(counter: 10_000, writer: "other")
        watch.merge(stale); watch.normalizeInboxRanking(writer: "watch")
        XCTAssertEqual(watch.snoozedCaptures.map(\.id), ["a"])
        watch.bringBackCapture("a", writer: "watch")
        XCTAssertTrue(watch.unseenCaptures.contains { $0.id == "a" })
        watch.prepareRanking(writer: "watch")
        XCTAssertEqual(watch.rankingPair?.first, "a")
        phone.merge(watch); phone.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(phone.rankingPair, watch.rankingPair)
        XCTAssertEqual(phone.captures.first { $0.id == "a" }?.notes, "Progress\nTwo steps done")
    }

    func testOldCaptureDataDecodesAndNotesDoNotAlterRankOrCreation() throws {
        var ledger = try ranked()
        let data = try JSONEncoder().encode(ledger)
        let old = try JSONDecoder().decode(Ledger.self, from: data)
        XCTAssertNil(old.captures[0].notes)
        XCTAssertNil(old.captures[0].snoozedUntil)
        XCTAssertNil(old.captures[0].reviewRevision)
        let before = ledger.rankedCaptureIDs, created = ledger.captures[0].createdAt
        try ledger.updateCapture(id: ledger.captures[0].id, text: ledger.captures[0].text, notes: "  Progress  ", writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs, before)
        XCTAssertEqual(ledger.captures[0].createdAt, created)
        XCTAssertEqual(ledger.captures[0].notes, "Progress")
        XCTAssertTrue(ledger.inboxExport.text.contains("Notes: Progress"))
        try ledger.updateCapture(id: ledger.captures[0].id, text: ledger.captures[0].text, notes: "\n ", writer: "phone")
        XCTAssertNil(ledger.captures[0].notes)
    }

    func testSnoozedListOrdersByReturnAndDeletionUndoDoesNotLoseMetadata() throws {
        var ledger = try ranked()
        let now = Date()
        ledger.snoozeCapture("a", until: now.addingTimeInterval(2 * 86400), writer: "phone")
        ledger.snoozeCapture("b", until: now.addingTimeInterval(86400), writer: "phone")
        XCTAssertEqual(ledger.snoozedCaptures.map(\.id), ["b", "a"])
        ledger.setCaptureDeleted("b", deleted: true, writer: "phone")
        XCTAssertEqual(ledger.snoozedCaptures.map(\.id), ["a"])
        ledger.setCaptureDeleted("b", deleted: false, writer: "phone")
        XCTAssertEqual(ledger.snoozedCaptures.map(\.id), ["b", "a"])
        ledger.setCaptureDone(id: "b", done: true, writer: "phone")
        XCTAssertEqual(ledger.snoozedCaptures.map(\.id), ["a"])
        ledger.bringBackCapture("a", writer: "phone")
        XCTAssertTrue(ledger.snoozedCaptures.isEmpty)
        XCTAssertEqual(ledger.captures.count, 3)
    }
}
