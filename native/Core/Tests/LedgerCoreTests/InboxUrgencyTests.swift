import XCTest
@testable import LedgerCore

final class InboxUrgencyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testUserExamplesAreASAPWithoutDeadlineAndExplainWhy() {
        for (text, reason) in [("Get back to Alan", InboxUrgency.Reason.communication), ("reply back to Joe", .communication),
                               ("Schedule meeting with Jo", .meeting), ("Pay the rent", .payment), ("Pay the bill", .payment)] {
            let match = OfflineInboxUrgency.suggestion(text: text)
            XCTAssertEqual(match?.timing, .asap, text); XCTAssertEqual(match?.reason, reason, text)
            XCTAssertTrue(match?.isSuggested == true); XCTAssertNil(match?.timing.dueAt)
        }
    }
    func testOfflinePatternsDoNotTreatMissingDatesOrUnrelatedNounsAsUrgent() {
        for text in ["Practice guitar", "Buy contact lenses", "Call for proposals", "Pay attention to the music", "No need to reply to Joe", "I already replied to Joe", "Not urgent"] {
            XCTAssertNil(OfflineInboxUrgency.suggestion(text: text), text)
        }
        XCTAssertEqual(OfflineInboxUrgency.suggestion(text: "Remember to reply to Alan")?.reason, .communication)
        XCTAssertEqual(OfflineInboxUrgency.suggestion(text: "Check the files ASAP")?.reason, .explicit)
    }
    func testCustomPhrasesCanReplaceRemoveOrDisableDefaults() {
        XCTAssertNil(OfflineInboxUrgency.suggestion(text: "Get back to Alan", phrases: []))
        XCTAssertEqual(OfflineInboxUrgency.suggestion(text: "Please renew passport!", phrases: ["renew passport"])?.timing, .asap)
        XCTAssertNil(OfflineInboxUrgency.suggestion(text: "Renew passports", phrases: ["renew passport"]))
    }
    func testNoDateCorrectionSurvivesEditsAndAutomaticCanBeRestored() throws {
        var ledger = Ledger(); try ledger.addCapture(text: "Reply to Joe", id: "a", writer: "phone")
        XCTAssertEqual(ledger.urgentCaptures().map(\.id), ["a"])
        try ledger.setCaptureTiming("a", timing: .noDate, writer: "phone")
        try ledger.updateCaptureText(id: "a", text: "Reply to Alan", writer: "phone")
        XCTAssertTrue(ledger.urgentCaptures().isEmpty)
        try ledger.setCaptureTiming("a", timing: nil, writer: "phone")
        XCTAssertEqual(ledger.urgentCaptures().map(\.id), ["a"])
    }
    func testDueDateAndExplicitASAPAreDistinctAndDoNotChangeRankingOrCategories() throws {
        var ledger = Ledger(); try ledger.addCapture(text: "Practice guitar", id: "a", writer: "p")
        let ranking = ledger.inboxRanking, categories = ledger.categories
        try ledger.setCaptureTiming("a", timing: .due(now.addingTimeInterval(86400 * 30)), writer: "p")
        XCTAssertEqual(ledger.urgentCaptures().first?.timing?.dueAt, now.addingTimeInterval(86400 * 30))
        try ledger.setCaptureTiming("a", timing: .asap, writer: "p")
        XCTAssertNil(ledger.captures[0].timing?.dueAt); XCTAssertEqual(ledger.captures[0].timing, .asap)
        XCTAssertEqual(ledger.inboxRanking, ranking); XCTAssertEqual(ledger.categories, categories)
    }
    func testUrgentIncludesUnrankedButExcludesCompletedDeletedReferenceAndSnoozed() throws {
        var ledger = Ledger()
        for id in ["unseen", "done", "deleted", "reference", "snoozed"] { try ledger.addCapture(text: "Reply to \(id)", id: id, writer: "p", now: now) }
        ledger.setCaptureDone(id: "done", done: true, writer: "p")
        ledger.setCaptureDeleted("deleted", deleted: true, writer: "p")
        ledger.setCaptureReference("reference", reference: true, writer: "p")
        ledger.snoozeCapture("snoozed", until: now.addingTimeInterval(86400 * 7), writer: "p", now: now)
        XCTAssertEqual(ledger.urgentCaptures(at: now).map(\.id), ["unseen"])
        XCTAssertEqual(Set(ledger.urgentCaptures(at: now.addingTimeInterval(86400 * 8)).map(\.id)), ["unseen", "snoozed"])
    }
    func testTimingSettingsAndManualCorrectionSurviveBackupMergeAndFastSync() throws {
        var ledger = Ledger(); try ledger.addCapture(text: "Call Alan", id: "a", writer: "phone")
        let stale = ledger
        try ledger.setCaptureTiming("a", timing: .noDate, writer: "phone")
        var settings = ledger.settings; settings.urgencyPhrases = ["Send invoice"]
        settings.categoryMatchRules = [.init(phrase: "guitar", categoryID: "music")]; settings.categoryMatching = .broader
        try ledger.saveSettings(settings, writer: "phone")
        var restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        restored.merge(stale)
        XCTAssertEqual(restored.captures.first?.timing, .noDate); XCTAssertEqual(restored.settings, ledger.settings)
        var delivery = CompanionQuickDelivery()
        let packet = try JSONDecoder().decode(CompanionQuickPacket.self, from: XCTUnwrap(try delivery.prepare(ledger, id: "packet")))
        XCTAssertEqual(packet.ledger.captures.first?.timing, .noDate)
        XCTAssertEqual(packet.ledger.settings, ledger.settings)
        XCTAssertTrue(restored.inboxExport.text.contains("Timing: No date"))
    }
    func testOldCaptureAndSettingsDecodeWithoutNewFields() throws {
        var ledger = Ledger(); try ledger.addCapture(text: "Practice guitar", id: "a", writer: "p")
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertNil(restored.captures[0].timing); XCTAssertNil(restored.settings.urgencyPhrases)
        XCTAssertNil(restored.settings.categoryMatchRules); XCTAssertEqual(restored.settings.effectiveCategoryMatching, .broader)
        XCTAssertTrue(restored.urgentCaptures().isEmpty)
    }
}
