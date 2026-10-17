import XCTest
@testable import LedgerCore

final class ReminderImportTests: XCTestCase {
    private let created = Date(timeIntervalSince1970: 1_792_060_000)
    private var later: Date { created.addingTimeInterval(86400) }

    func testImportPreservesCreationTimeFullTextAndLeavesActivitySamplesAlone() throws {
        var ledger = Ledger()
        let reminder = ReminderSnapshot(identifiers: ["external", "local"], title: "Change bicycle wheels",
                                        notes: "Check the tyre size first", createdAt: created)
        XCTAssertEqual(ledger.importReminders([reminder], writer: "phone", now: later), 1)
        let idea = try XCTUnwrap(ledger.captures.first)
        XCTAssertEqual(idea.text, "Change bicycle wheels\nCheck the tyre size first")
        XCTAssertEqual(idea.createdAt, created)
        XCTAssertFalse(idea.isDone)
        XCTAssertTrue(ledger.entries.isEmpty)
        XCTAssertEqual(ledger.reminderImports?.count, 2)
        XCTAssertEqual(ledger.inboxExport.count, 1)
    }

    func testRepeatedImportsDoNotReopenCompletedIdeasOrResurrectDeletedIdeas() throws {
        var ledger = Ledger()
        let first = ReminderSnapshot(identifiers: ["first"], title: "First thought", createdAt: created)
        let second = ReminderSnapshot(identifiers: ["second"], title: "Second thought", createdAt: created)
        XCTAssertEqual(ledger.importReminders([first, second], writer: "phone"), 2)
        ledger.setCaptureDone(id: "reminder-first", done: true, writer: "phone")
        ledger.setCaptureDeleted("reminder-second", deleted: true, writer: "phone")
        let saved = ledger
        XCTAssertEqual(ledger.importReminders([first, second], writer: "phone", now: later), 0)
        XCTAssertEqual(ledger, saved)
        XCTAssertTrue(ledger.activeCaptures.isEmpty)
    }

    func testLateExternalIdentityIsLearnedWithoutChangingTheOriginalIdea() throws {
        var ledger = Ledger()
        let local = ReminderSnapshot(identifiers: ["local"], title: "Original thought", createdAt: created)
        ledger.importReminders([local], writer: "phone")
        ledger.setCaptureDone(id: "reminder-local", done: true, writer: "phone")
        let saved = try XCTUnwrap(ledger.captures.first)
        let synced = ReminderSnapshot(identifiers: ["external", "local"], title: "Edited in Reminders", createdAt: later)
        XCTAssertEqual(ledger.importReminders([synced], writer: "phone"), 0)
        XCTAssertEqual(ledger.captures, [saved])
        XCTAssertEqual(ledger.reminderImports?.first(where: { $0.id == "external" })?.captureID, saved.id)
        XCTAssertEqual(ledger.importReminders([ReminderSnapshot(identifiers: ["external", "other-device"], title: "Other device copy")], writer: "phone"), 0)
        XCTAssertEqual(ledger.captures, [saved])
    }

    func testBackupAndDeviceMergeRetainImportReceiptsAndDeletion() throws {
        var phone = Ledger()
        let item = ReminderSnapshot(identifiers: ["external"], title: "A saved idea", createdAt: created)
        phone.importReminders([item], writer: "phone")
        var watch = phone
        watch.setCaptureDeleted("reminder-external", deleted: true, writer: "watch")
        phone.merge(watch)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded())
        var reopened = restored.ledger
        let before = reopened
        XCTAssertEqual(reopened.importReminders([item], writer: "phone", now: later), 0)
        XCTAssertEqual(reopened, before)
        let oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ledger())) as! [String: Any]
        var legacy = oldJSON; legacy.removeValue(forKey: "reminderImports")
        let oldCopy = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: legacy))
        reopened.merge(oldCopy)
        XCTAssertEqual(reopened.reminderImports, before.reminderImports)
        XCTAssertNotNil(reopened.captures.first?.deletedAt)
    }

    func testSourceCompletionAndInvalidRowsCannotBlockOtherIdeas() {
        var ledger = Ledger()
        let rows = [
            ReminderSnapshot(identifiers: ["done"], title: "Already finished", isCompleted: true),
            ReminderSnapshot(identifiers: [], title: "No identifier"),
            ReminderSnapshot(identifiers: ["empty"], title: " \n"),
            ReminderSnapshot(identifiers: ["valid"], title: "Good idea")
        ]
        XCTAssertEqual(ledger.importReminders(rows, writer: "phone", now: later), 1)
        XCTAssertEqual(ledger.captures.first?.text, "Good idea")
        XCTAssertEqual(ledger.captures.first?.createdAt, later)
    }

    func testLongReminderNotesAreNotTruncated() {
        var ledger = Ledger()
        let notes = String(repeating: "Keep this entire thought.\n", count: 100)
        XCTAssertEqual(ledger.importReminders([ReminderSnapshot(identifiers: ["long"], title: "Idea", notes: notes)], writer: "phone"), 1)
        XCTAssertEqual(ledger.captures.first?.text, "Idea\n" + notes.trimmingCharacters(in: .whitespacesAndNewlines))
        let exported = ledger.inboxExport.text.replacingOccurrences(of: "\n   ", with: "\n")
        XCTAssertTrue(exported.contains(notes.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}
