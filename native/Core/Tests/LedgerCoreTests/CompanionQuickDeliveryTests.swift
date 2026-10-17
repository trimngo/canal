import XCTest
@testable import LedgerCore

final class CompanionQuickDeliveryTests: XCTestCase {
    private func sample(_ ledger: inout Ledger, id: String, text: String = "Working") throws {
        try ledger.saveQuickSample(id: id, at: Date(), activity: text, writer: "watch")
    }
    private func packet(_ state: inout CompanionQuickDelivery, ledger: Ledger, id: String = "quick", limit: Int = 48_000) throws -> CompanionQuickPacket {
        let data = try XCTUnwrap(state.prepare(ledger, id: id, byteLimit: limit))
        XCTAssertLessThanOrEqual(data.count, limit)
        return try JSONDecoder().decode(CompanionQuickPacket.self, from: data)
    }

    func testNewLongWatchReplyBypassesAnOlderHistoryFileAndIsAcknowledgedAfterMerge() throws {
        var watch = Ledger(), phone = Ledger(), background = CompanionDeliveryState(), quick = CompanionQuickDelivery()
        for index in 0..<200 { try sample(&watch, id: "old-\(index)", text: String(repeating: "a", count: 490)) }
        let oldFile = try JSONEncoder().encode(watch)
        XCTAssertGreaterThan(oldFile.count, 48_000)
        XCTAssertTrue(background.begin(oldFile, id: "old-file"))
        try sample(&watch, id: "new-long", text: String(repeating: "🦉", count: 490))
        let latest = try XCTUnwrap(watch.entries.first { $0.id == "new-long" })
        let update = try packet(&quick, ledger: watch)
        XCTAssertTrue(update.ledger.entries.contains { $0.id == "new-long" })
        XCTAssertLessThan(update.ledger.entries.count, watch.entries.count)
        XCTAssertFalse(quick.hasReceived(latest))
        phone.merge(update.ledger)
        let disk = try JSONEncoder().encode(phone)
        phone = try JSONDecoder().decode(Ledger.self, from: disk)
        XCTAssertTrue(quick.finish(id: update.id, saved: true))
        XCTAssertTrue(quick.hasReceived(latest))
        XCTAssertEqual(phone.entries.first { $0.id == "new-long" }?.activity, latest.activity)
        // The original queued file can arrive afterwards without losing or
        // duplicating the entry delivered through the fast lane.
        phone.merge(try JSONDecoder().decode(Ledger.self, from: oldFile))
        XCTAssertEqual(phone.entries.count, 201)
        XCTAssertEqual(phone.entries.filter { $0.id == "new-long" }.count, 1)
    }

    func testFailureDoesNotAcknowledgeAndRetryIncludesChangesSavedWhileInFlight() throws {
        var watch = Ledger(), quick = CompanionQuickDelivery()
        try sample(&watch, id: "one")
        let one = try packet(&quick, ledger: watch, id: "one")
        XCTAssertNil(try quick.prepare(watch, id: "blocked"))
        try sample(&watch, id: "two")
        XCTAssertFalse(quick.finish(id: "unrelated", saved: true))
        XCTAssertNil(try quick.prepare(watch, id: "still-blocked"))
        XCTAssertFalse(quick.finish(id: one.id, saved: false))
        XCTAssertFalse(quick.recentLogsReceived(in: watch))
        let retry = try packet(&quick, ledger: watch, id: "retry")
        XCTAssertEqual(Set(retry.ledger.entries.map(\.id)), ["one", "two"])
        XCTAssertTrue(quick.finish(id: retry.id, saved: true))
        XCTAssertTrue(quick.recentLogsReceived(in: watch))
        XCTAssertNil(try quick.prepare(watch, id: "duplicate"))
    }

    func testLateReceiptCannotAcknowledgeAnEditOrFinishANewerTransfer() throws {
        var watch = Ledger(), quick = CompanionQuickDelivery()
        try sample(&watch, id: "one")
        _ = try packet(&quick, ledger: watch, id: "old")
        try watch.saveSample(id: "one", at: watch.entries[0].end, activity: "Edited reply", categoryID: nil, writer: "watch")
        XCTAssertTrue(quick.finish(id: "old", saved: true))
        XCTAssertFalse(quick.hasReceived(watch.entries[0]))
        _ = try packet(&quick, ledger: watch, id: "new")
        XCTAssertFalse(quick.finish(id: "old", saved: true))
        XCTAssertNil(try quick.prepare(watch, id: "cannot-replace-new"))
        XCTAssertTrue(quick.finish(id: "new", saved: true))
        XCTAssertTrue(quick.hasReceived(watch.entries[0]))
    }

    func testOversizedIdeaDoesNotBlockLogsAndRemainsInFullBackup() throws {
        var watch = Ledger(), quick = CompanionQuickDelivery()
        try watch.addCapture(text: "Large idea", id: "large", writer: "watch")
        try watch.updateCaptureText(id: "large", text: String(repeating: "Long idea\n", count: 10_000), writer: "watch")
        try sample(&watch, id: "reply")
        let update = try packet(&quick, ledger: watch, limit: 4_000)
        XCTAssertEqual(update.ledger.entries.map(\.id), ["reply"])
        XCTAssertTrue(update.ledger.captures.isEmpty)
        quick.finish(id: update.id, saved: true)
        XCTAssertFalse(quick.recentLogsReceived(in: watch))
        XCTAssertNil(try quick.prepare(watch, id: "oversize-only", byteLimit: 4_000))
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: watch).encoded()).ledger
        XCTAssertEqual(restored.captures, watch.captures)
    }

    func testImmediateEditsDeletionRestoreAndIdeasReuseExistingMergeWithoutChangingSettings() throws {
        var watch = Ledger(), phone = Ledger(), quick = CompanionQuickDelivery()
        try sample(&watch, id: "reply")
        try watch.addCapture(text: "Idea", id: "idea", writer: "watch")
        var settings = phone.settings; settings.use24HourTime = true
        try phone.saveSettings(settings, writer: "phone")
        let preserved = phone.settings
        let first = try packet(&quick, ledger: watch, id: "first")
        phone.merge(first.ledger); quick.finish(id: first.id, saved: true)
        XCTAssertEqual(phone.settings, preserved)
        XCTAssertEqual(phone.captures.map(\.id), ["idea"])
        watch.setLogDeleted("reply", deleted: true, writer: "watch")
        watch.setCaptureDeleted("idea", deleted: true, writer: "watch")
        let removed = try packet(&quick, ledger: watch, id: "removed")
        phone.merge(removed.ledger); quick.finish(id: removed.id, saved: true)
        XCTAssertTrue(phone.activeEntries.isEmpty)
        XCTAssertTrue(phone.activeCaptures.isEmpty)
        watch.setLogDeleted("reply", deleted: false, writer: "watch")
        watch.setCaptureDeleted("idea", deleted: false, writer: "watch")
        let restored = try packet(&quick, ledger: watch, id: "restored")
        phone.merge(restored.ledger)
        XCTAssertEqual(phone.activeEntries.map(\.id), ["reply"])
        XCTAssertEqual(phone.activeCaptures.map(\.id), ["idea"])
        XCTAssertEqual(phone.settings, preserved)
    }
}
