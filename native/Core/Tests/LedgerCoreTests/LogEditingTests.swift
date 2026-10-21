import XCTest
@testable import LedgerCore

final class LogEditingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        try ledger.saveSample(id: "sample", at: now, activity: "Original words", categoryIDs: ["work", "social"], writer: "watch", now: now)
        try ledger.setMood(for: "sample", value: 4, writer: "phone")
        return ledger
    }

    func testTextOnlyEditKeepsTimestampLabelsMoodAndIdentity() throws {
        var ledger = try fixture()
        let original = ledger.entries[0]
        try ledger.updateLogActivity(id: "sample", activity: "  Corrected dictation\n", writer: "phone")
        var updated = ledger.entries[0]
        XCTAssertEqual(updated.activity, "Corrected dictation")
        XCTAssertGreaterThan(updated.revision, original.revision)
        updated.activity = original.activity; updated.revision = original.revision
        XCTAssertEqual(updated, original)
        XCTAssertEqual(ledger.entries.count, 1)
    }

    func testInvalidMissingAndDeletedEntriesCannotBeEditedOrResurrected() throws {
        var ledger = try fixture(), original = ledger
        for text in ["", " \n ", String(repeating: "a", count: 501)] {
            XCTAssertThrowsError(try ledger.updateLogActivity(id: "sample", activity: text, writer: "phone"))
            XCTAssertEqual(ledger, original)
        }
        XCTAssertThrowsError(try ledger.updateLogActivity(id: "missing", activity: "New words", writer: "phone"))
        ledger.setLogDeleted("sample", deleted: true, writer: "phone"); original = ledger
        XCTAssertThrowsError(try ledger.updateLogActivity(id: "sample", activity: "New words", writer: "phone"))
        XCTAssertEqual(ledger, original)
    }

    func testNoOpAndLegacyUnconfirmedTextKeepExistingAssignments() throws {
        var ledger = Ledger()
        ledger.entries = [CheckIn(end: now, activity: "Raw words", categoryID: "work", revision: Revision(counter: 1, writer: "watch"), categoryAssignment: .automatic)]
        let original = ledger
        try ledger.updateLogActivity(id: ledger.entries[0].id, activity: " Raw words ", writer: "phone")
        XCTAssertEqual(ledger, original)
        try ledger.updateLogActivity(id: ledger.entries[0].id, activity: "Corrected words", writer: "phone")
        XCTAssertEqual(ledger.entries[0].categoryAssignment, .automatic)
        XCTAssertEqual(ledger.entries[0].categoryID, "work")
        XCTAssertNil(ledger.entries[0].categoryIDs)
        XCTAssertTrue(ledger.confirmedCategoryIDs(for: ledger.entries[0]).isEmpty)
    }

    func testLatestLabelsAndDeletedSharesSurviveTextEditBackupAndQuickSync() throws {
        var phone = try fixture()
        try phone.deleteCategory(id: "social", writer: "phone")
        let latest = phone.entries[0]
        try phone.updateLogActivity(id: latest.id, activity: "Corrected after recategorization", writer: "phone")
        XCTAssertEqual(phone.entries[0].categoryIDs, latest.categoryIDs)
        XCTAssertEqual(phone.allocationCategoryIDs(for: phone.entries[0]), ["work", "uncategorized"])
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        XCTAssertEqual(restored.entries, phone.entries)
        var quick = CompanionQuickDelivery()
        let packet = try JSONDecoder().decode(CompanionQuickPacket.self, from: XCTUnwrap(quick.prepare(phone, id: "edited")))
        var watch = Ledger(); watch.merge(packet.ledger)
        XCTAssertEqual(watch.entries, phone.entries)
    }
}
