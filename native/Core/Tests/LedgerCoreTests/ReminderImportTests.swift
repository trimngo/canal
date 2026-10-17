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

    func testSourceRemovalRequiresAnImportedSavedCopyWithExactText() throws {
        var ledger = Ledger()
        let item = ReminderSnapshot(identifiers: ["external", "local"], title: "  Bicycle  ", notes: " Check wheel size\n", createdAt: created)
        XCTAssertFalse(ledger.canRemoveImportedReminder(item))
        ledger.importReminders([item], writer: "phone")
        XCTAssertTrue(ledger.canRemoveImportedReminder(item))
        let saved = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertTrue(saved.canRemoveImportedReminder(item))
        ledger.captures.removeAll()
        XCTAssertFalse(ledger.canRemoveImportedReminder(item))
    }

    func testChangedSourceOrDashCopyIsKeptInsteadOfLosingEdits() {
        var ledger = Ledger()
        let original = ReminderSnapshot(identifiers: ["one"], title: "Original", notes: "Details")
        ledger.importReminders([original], writer: "phone")
        let changed = ReminderSnapshot(identifiers: ["one"], title: "New Watch edit", notes: "Details")
        XCTAssertFalse(ledger.canRemoveImportedReminder(changed))
        XCTAssertEqual(ledger.importReminders([changed], writer: "phone"), 0)
        XCTAssertFalse(ledger.canRemoveImportedReminder(changed))
        ledger.captures[0].text = "Edited in Dash"
        XCTAssertFalse(ledger.canRemoveImportedReminder(original))
        XCTAssertEqual(ledger.captures.count, 1)
    }

    func testDeletionRetriesDoNotDuplicateOrReopenIdeas() {
        var ledger = Ledger()
        let item = ReminderSnapshot(identifiers: ["source"], title: "A saved thought")
        ledger.importReminders([item], writer: "phone")
        ledger.setCaptureDone(id: "reminder-source", done: true, writer: "phone")
        ledger.setCaptureDeleted("reminder-source", deleted: true, writer: "phone")
        let before = ledger
        for _ in 0..<3 {
            XCTAssertEqual(ledger.importReminders([item], writer: "phone"), 0)
            XCTAssertTrue(ledger.canRemoveImportedReminder(item))
        }
        XCTAssertEqual(ledger, before)
    }

    func testCompletedEmptyAndAmbiguousSourcesAreNeverRemoved() {
        var ledger = Ledger()
        let a = ReminderSnapshot(identifiers: ["a"], title: "A"), b = ReminderSnapshot(identifiers: ["b"], title: "B")
        ledger.importReminders([a, b], writer: "phone")
        XCTAssertFalse(ledger.canRemoveImportedReminder(ReminderSnapshot(identifiers: ["a"], title: "A", isCompleted: true)))
        XCTAssertFalse(ledger.canRemoveImportedReminder(ReminderSnapshot(identifiers: ["a"], title: " \n")))
        XCTAssertFalse(ledger.canRemoveImportedReminder(ReminderSnapshot(identifiers: [], title: "A")))
        XCTAssertFalse(ledger.canRemoveImportedReminder(ReminderSnapshot(identifiers: ["a", "b"], title: "A")))
        XCTAssertTrue(ledger.canRemoveImportedReminder(a))
    }

    func testLongReminderNotesAreNotTruncated() {
        var ledger = Ledger()
        let notes = String(repeating: "Keep this entire thought.\n", count: 100)
        XCTAssertEqual(ledger.importReminders([ReminderSnapshot(identifiers: ["long"], title: "Idea", notes: notes)], writer: "phone"), 1)
        XCTAssertEqual(ledger.captures.first?.text, "Idea\n" + notes.trimmingCharacters(in: .whitespacesAndNewlines))
        let exported = ledger.inboxExport.text.replacingOccurrences(of: "\n   ", with: "\n")
        XCTAssertTrue(exported.contains(notes.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func testTransferredIdeaCorrectionsPreserveIdentityDateRankAndSync() throws {
        var ledger = Ledger()
        let source = ReminderSnapshot(identifiers: ["edit"], title: "Siri transcription", createdAt: created)
        ledger.importReminders([source], writer: "phone")
        ledger.prepareRanking(writer: "phone")
        let before = try XCTUnwrap(ledger.captures.first)
        let rank = ledger.rankedCaptureIDs
        var watch = ledger
        let corrected = "Corrected thought\n" + String(repeating: "Keep long notes. ", count: 80)
        try ledger.updateCaptureText(id: before.id, text: corrected, writer: "phone")
        XCTAssertEqual(ledger.captures.first?.id, before.id)
        XCTAssertEqual(ledger.captures.first?.createdAt, created)
        XCTAssertEqual(ledger.rankedCaptureIDs, rank)
        XCTAssertEqual(ledger.captures.first?.text, corrected.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertFalse(ledger.canRemoveImportedReminder(source))
        watch.merge(try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger)
        XCTAssertEqual(watch.captures, ledger.captures)
        XCTAssertEqual(watch.importReminders([source], writer: "watch"), 0)
        XCTAssertEqual(watch.captures, ledger.captures)
        XCTAssertThrowsError(try ledger.updateCaptureText(id: before.id, text: " \n", writer: "phone"))
        ledger.setCaptureDeleted(before.id, deleted: true, writer: "phone")
        XCTAssertThrowsError(try ledger.updateCaptureText(id: before.id, text: "Do not resurrect", writer: "phone"))
        XCTAssertNotNil(ledger.captures.first?.deletedAt)
    }
}
