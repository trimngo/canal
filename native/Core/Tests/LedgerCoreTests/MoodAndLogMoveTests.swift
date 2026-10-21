import XCTest
@testable import LedgerCore

final class MoodAndLogMoveTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        ledger.categories += [LedgerCategory(id: "hygiene", name: "Hygiene"), LedgerCategory(id: "basics", name: "Basics")]
        try ledger.moveCategory("hygiene", to: "basics", writer: "phone")
        for id in ["one", "two"] {
            try ledger.saveSample(id: id, at: now, activity: "Original \(id)", categoryIDs: ["personal", "social"], writer: "watch", now: now)
        }
        return ledger
    }

    func testMoodCanBeSetChangedClearedAndSurvivesActivityEditing() throws {
        var ledger = try fixture()
        let original = ledger.entries[0]
        try ledger.setMood(for: "one", value: 4, writer: "phone")
        try ledger.saveSample(id: "one", at: now, activity: "Edited activity", categoryIDs: ["work"], writer: "phone", now: now)
        XCTAssertEqual(ledger.entries.first { $0.id == "one" }?.mood, 4)
        XCTAssertEqual(ledger.entries.first { $0.id == "one" }?.end, original.end)
        try ledger.setMood(for: "one", value: 1, writer: "phone")
        XCTAssertEqual(ledger.entries.first { $0.id == "one" }?.mood, 1)
        try ledger.setMood(for: "one", value: nil, writer: "phone")
        XCTAssertNil(ledger.entries.first { $0.id == "one" }?.mood)
        let before = ledger
        for value in [-1, 0, 6] { XCTAssertThrowsError(try ledger.setMood(for: "one", value: value, writer: "phone")) }
        XCTAssertEqual(ledger, before)
    }

    func testCaptureTextIsNotParsedForMoodAndLegacyLogsDecodeWithoutMood() throws {
        var ledger = Ledger()
        try ledger.saveQuickSample(id: "sample", at: now, activity: "Practicing German, mood four", writer: "watch", now: now)
        XCTAssertEqual(ledger.entries[0].activity, "Practicing German, mood four"); XCTAssertNil(ledger.entries[0].mood)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(restored.entries, ledger.entries)
    }

    func testMoodSurvivesBackupQuickDeliveryPartialCloudMergeAndRetry() throws {
        var phone = try fixture()
        try phone.setMood(for: "one", value: 5, writer: "phone")
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        XCTAssertEqual(restored, phone)
        var quick = CompanionQuickDelivery()
        let data = try XCTUnwrap(quick.prepare(phone, id: "packet"))
        let packet = try JSONDecoder().decode(CompanionQuickPacket.self, from: data)
        var watch = Ledger(); watch.merge(packet.ledger)
        XCTAssertEqual(watch.entries.first { $0.id == "one" }?.mood, 5)
        var partial = Ledger(); partial.categories = []; partial.entries = phone.entries
        watch.merge(partial)
        XCTAssertEqual(watch.entries.first { $0.id == "one" }?.mood, 5)
        try watch.saveQuickSample(id: "one", at: now, activity: "Replay", writer: "watch", now: now)
        XCTAssertEqual(watch.entries.first { $0.id == "one" }?.mood, 5)
        try watch.setMood(for: "one", value: nil, writer: "watch")
        phone.merge(watch)
        XCTAssertNil(phone.entries.first { $0.id == "one" }?.mood)
    }

    func testBulkMovePreservesOtherLabelsMoodActivityAndTimestamp() throws {
        var ledger = try fixture(); try ledger.setMood(for: "one", value: 3, writer: "phone")
        let originals = ledger.entries
        try ledger.moveLogs(["one", "two"], from: "personal", to: "hygiene", writer: "phone")
        for original in originals {
            let updated = try XCTUnwrap(ledger.entries.first { $0.id == original.id })
            XCTAssertEqual(ledger.confirmedCategoryIDs(for: updated), ["hygiene", "social"])
            XCTAssertEqual(updated.end, original.end); XCTAssertEqual(updated.activity, original.activity); XCTAssertEqual(updated.mood, original.mood)
        }
        XCTAssertEqual(try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger, ledger)
    }

    func testMovingParentLogsReplacesItsDescendantLabelsAndRejectsConflictsAtomically() throws {
        var ledger = try fixture()
        try ledger.moveLogs(["one"], from: "personal", to: "hygiene", writer: "phone")
        try ledger.moveLogs(["one"], from: "basics", to: "work", writer: "phone")
        XCTAssertEqual(ledger.confirmedCategoryIDs(for: ledger.entries.first { $0.id == "one" }!), ["social", "work"])
        try ledger.moveCategory("basics", to: "social", writer: "phone")
        let before = ledger
        XCTAssertThrowsError(try ledger.moveLogs(["two"], from: "personal", to: "hygiene", writer: "phone"))
        XCTAssertEqual(ledger, before)
        XCTAssertThrowsError(try ledger.moveLogs(["one", "two"], from: "personal", to: "work", writer: "phone"))
        XCTAssertEqual(ledger, before)
    }

    func testUncategorizedAndDeletedSharesCanMoveWithoutLosingOtherLabels() throws {
        var ledger = try fixture()
        try ledger.deleteCategory(id: "personal", writer: "phone")
        try ledger.moveLogs(["one"], from: "uncategorized", to: "hygiene", writer: "phone")
        XCTAssertEqual(ledger.confirmedCategoryIDs(for: ledger.entries.first { $0.id == "one" }!), ["hygiene", "social"])
        try ledger.saveQuickSample(id: "raw", at: now, activity: "Uncategorized", writer: "watch", now: now)
        try ledger.moveLogs(["raw"], from: "uncategorized", to: "hygiene", writer: "phone")
        XCTAssertEqual(ledger.confirmedCategoryIDs(for: ledger.entries.first { $0.id == "raw" }!), ["hygiene"])
        let before = ledger
        ledger.setLogDeleted("two", deleted: true, writer: "phone")
        let deleted = ledger
        XCTAssertThrowsError(try ledger.moveLogs(["one", "two"], from: "uncategorized", to: "hygiene", writer: "phone"))
        XCTAssertEqual(ledger, deleted); XCTAssertEqual(ledger.entries, before.entries)
    }
}
