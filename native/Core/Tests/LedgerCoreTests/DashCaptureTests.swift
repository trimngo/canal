import XCTest
@testable import LedgerCore

final class DashCaptureTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_792_060_000)

    func testSpokenRoutingWordsAreRemovedWithoutLosingContent() throws {
        let idea = try QuickCapture.note(title: "IDEA, Try shorter lessons", body: nil, at: timestamp)
        XCTAssertEqual(idea.destination, .idea)
        XCTAssertEqual(idea.text, "Try shorter lessons")
        let activity = try QuickCapture.note(title: "doing", body: "Changing wheels on bicycle", at: timestamp)
        XCTAssertEqual(activity.destination, .activity)
        XCTAssertEqual(activity.text, "Changing wheels on bicycle")
        XCTAssertEqual(activity.recordedAt, timestamp)
        let plain = try QuickCapture.note(title: "Try shorter lessons", body: nil)
        XCTAssertEqual(plain.destination, .idea)
        XCTAssertEqual(plain.text, "Try shorter lessons")
        XCTAssertEqual(try QuickCapture.note(title: "Ideas for a class", body: nil).text, "Ideas for a class")
    }

    func testRoutingWordAloneCannotSaveEmptyContent() {
        for text in ["idea", "doing", " Doing:  ", "IDEA,\n"] {
            XCTAssertThrowsError(try QuickCapture.note(title: text, body: nil))
        }
    }

    func testActivityAndIdeaRemainSeparateThroughQueueReplayAndBackup() throws {
        var ledger = Ledger()
        let idea = try QuickCapture.note(title: "idea: Call Alex", body: nil, id: "idea", at: timestamp)
        let activity = try QuickCapture.note(title: "doing: Preparing classes", body: nil, id: "activity", at: timestamp)
        try ledger.saveQuickCapture(idea, writer: "watch", now: timestamp)
        try ledger.saveQuickCapture(activity, writer: "watch", now: timestamp)
        XCTAssertEqual(ledger.captures.map(\.text), ["Call Alex"])
        XCTAssertEqual(ledger.captures.first?.createdAt, timestamp)
        XCTAssertEqual(ledger.entries.map(\.activity), ["Preparing classes"])
        XCTAssertEqual(ledger.entries.first?.end, timestamp)
        XCTAssertNil(ledger.confirmedCategoryID(for: try XCTUnwrap(ledger.entries.first)))
        ledger.setCaptureDone(id: "idea", done: true, writer: "phone")
        ledger.setLogDeleted("activity", deleted: true, writer: "phone")
        let before = ledger
        try ledger.saveQuickCapture(idea, writer: "watch", now: timestamp)
        try ledger.saveQuickCapture(activity, writer: "watch", now: timestamp)
        XCTAssertEqual(ledger, before)
        let backup = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded())
        XCTAssertEqual(backup.ledger, ledger)
    }

    func testOldWatchQueueKeepsIdeasAsIdeasAndNewQueueKeepsActivityTimestamp() throws {
        let old = Capture(id: "legacy", text: "Doing something new might help", createdAt: timestamp,
                          revision: Revision(counter: 1, writer: "watch-siri"))
        let migrated = try QuickCaptureEntry.decodeQueued(JSONEncoder().encode(old))
        XCTAssertEqual(migrated.destination, .idea)
        XCTAssertEqual(migrated.id, old.id)
        XCTAssertEqual(migrated.recordedAt, timestamp)
        XCTAssertEqual(migrated.text, old.text)
        let activity = try QuickCapture.note(title: "doing, Cycling", body: nil, at: timestamp)
        XCTAssertEqual(try QuickCaptureEntry.decodeQueued(JSONEncoder().encode(activity)), activity)
    }

    func testInboxExportKeepsEveryLineCompletedIdeasRanksAndOriginalDates() throws {
        var ledger = Ledger()
        try ledger.addCapture(text: "Most important\nSecond line", id: "a", writer: "phone", now: timestamp)
        try ledger.addCapture(text: "Another idea", id: "b", writer: "phone", now: timestamp)
        ledger.prepareRanking(writer: "phone")
        let pair = try XCTUnwrap(ledger.rankingPair)
        ledger.chooseCapture("a", from: pair, writer: "phone")
        try ledger.addCapture(text: "Finished thought", id: "done", writer: "phone", now: timestamp)
        ledger.setCaptureDone(id: "done", done: true, writer: "phone")
        try ledger.addCapture(text: "Do not export deleted text", id: "deleted", writer: "phone", now: timestamp)
        ledger.setCaptureDeleted("deleted", deleted: true, writer: "phone")
        let before = ledger
        let export = ledger.inboxExport
        XCTAssertEqual(export.count, 3)
        XCTAssertTrue(export.text.hasPrefix("Dash inbox — 3 ideas\n\n1. Most important\n   Second line"))
        XCTAssertTrue(export.text.contains("2. Another idea"))
        XCTAssertTrue(export.text.contains("3. Finished thought"))
        XCTAssertTrue(export.text.contains("Status: Completed"))
        XCTAssertTrue(export.text.contains("Rank: 1"))
        XCTAssertTrue(export.text.contains("Captured: \(ISO8601DateFormatter().string(from: timestamp))"))
        XCTAssertFalse(export.text.contains("Do not export deleted text"))
        XCTAssertEqual(ledger, before)
    }
}
