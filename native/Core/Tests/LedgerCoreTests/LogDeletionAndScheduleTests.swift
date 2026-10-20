import XCTest
@testable import LedgerCore

final class LogDeletionAndScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        try ledger.saveSample(id: "a", at: now.addingTimeInterval(-3600), activity: "Quokka notes", categoryID: "work", writer: "phone", now: now)
        try ledger.saveSample(id: "b", at: now.addingTimeInterval(-1800), activity: "Lunch", categoryID: "personal", writer: "phone", now: now)
        try ledger.saveSample(id: "c", at: now, activity: "Rest", categoryID: "rest", writer: "phone", now: now)
        return ledger
    }
    func testDeletingNightObservationStartsEstimatesAtFirstRemainingMorningLog() throws {
        let formatter = ISO8601DateFormatter()
        let morning = formatter.date(from: "2026-10-20T08:00:00Z")!
        let now = morning.addingTimeInterval(2 * 3600)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for method in InferenceMethod.allCases {
            var ledger = Ledger(); ledger.settings.inferenceMethod = method
            try ledger.saveSample(id: "night", at: morning.addingTimeInterval(-5 * 3600), activity: "Awake briefly", categoryID: "rest", writer: "phone", now: now)
            try ledger.saveSample(id: "breakfast", at: morning, activity: "Breakfast", categoryID: "personal", writer: "phone", now: now)
            try ledger.saveSample(id: "work", at: morning.addingTimeInterval(3600), activity: "Work", categoryID: "work", writer: "phone", now: now)
            let raw = ledger.entries
            XCTAssertEqual(ledger.history(range: .today, now: now, calendar: calendar).trackedMinutes, 420, accuracy: 0.001)
            ledger.setLogDeleted("night", deleted: true, writer: "phone")
            let report = ledger.history(range: .today, now: now, calendar: calendar)
            XCTAssertEqual(report.trackedMinutes, 120, accuracy: 0.001)
            XCTAssertEqual(report.samples.map(\.end).min(), morning)
            XCTAssertFalse(report.rows.contains { $0.id == "rest" })
            XCTAssertEqual(report.rows.reduce(0) { $0 + $1.percent }, 100, accuracy: 0.001)
            XCTAssertEqual(ledger.entries, raw)
            ledger.setLogDeleted("night", deleted: false, writer: "phone")
            XCTAssertEqual(ledger.history(range: .today, now: now, calendar: calendar).trackedMinutes, 420, accuracy: 0.001)
        }
    }
    func testDeletingSampleRecalculatesEstimatesAndAllTimeCountsWithoutLosingRawData() throws {
        var ledger = try fixture()
        let raw = ledger.entries
        XCTAssertEqual(ledger.history(range: .allTime, now: now).rows.first { $0.id == "personal" }?.minutes, 30)
        ledger.setLogDeleted("b", deleted: true, writer: "phone")
        let report = ledger.history(range: .allTime, now: now)
        XCTAssertEqual(Set(report.samples.map(\.id)), Set(["a", "c"]))
        XCTAssertEqual(report.trackedMinutes, 60, accuracy: 0.001)
        XCTAssertFalse(report.rows.contains { $0.id == "personal" })
        XCTAssertEqual(ledger.groupEntryCounts(now: now), ["work": 1, "rest": 1])
        XCTAssertEqual(ledger.entries, raw)
        XCTAssertFalse(ledger.entries(on: now).contains { $0.id == "b" })
    }
    func testStaleAndNewerOfflineEditsCannotReviveDeletionAndBackupKeepsIt() throws {
        var phone = try fixture(), watch = phone
        phone.setLogDeleted("a", deleted: true, writer: "phone")
        for i in 0..<8 { try watch.saveSample(id: "a", at: now.addingTimeInterval(-3600), activity: "Offline edit \(i)", categoryID: "work", writer: "watch", now: now) }
        let stale = watch
        phone.merge(watch); watch.merge(phone)
        XCTAssertEqual(phone, watch)
        XCTAssertTrue(phone.isLogDeleted("a"))
        var restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        restored.merge(stale)
        XCTAssertFalse(restored.activeEntries.contains { $0.id == "a" })
        XCTAssertThrowsError(try restored.saveSample(id: "a", at: now, activity: "Edit deleted", categoryID: nil, writer: "phone", now: now))
        try restored.saveQuickSample(id: "a", at: now, activity: "Replayed notification", writer: "phone", now: now)
        XCTAssertTrue(restored.isLogDeleted("a"))
    }
    func testUndoSurvivesSyncAndOldDeletionReplayAndEmptyDayHasNoEstimates() throws {
        var phone = try fixture()
        let original = phone.activeEntries
        phone.setLogDeleted("a", deleted: true, writer: "phone")
        let deleted = phone
        phone.setLogDeleted("a", deleted: false, writer: "phone")
        phone.merge(deleted)
        XCTAssertEqual(Set(phone.activeEntries.map(\.id)), Set(original.map(\.id)))
        var watch = deleted; watch.merge(phone)
        XCTAssertFalse(watch.isLogDeleted("a"))
        for entry in phone.activeEntries { phone.setLogDeleted(entry.id, deleted: true, writer: "phone") }
        XCTAssertTrue(phone.history(range: .allTime, now: now).rows.isEmpty)
        XCTAssertTrue(phone.groupEntryCounts(now: now).isEmpty)
    }
    func testDeletedSamplesDoNotTeachOrReceiveGroupingButUndoRestoresTheirChoice() throws {
        var ledger = try fixture()
        XCTAssertEqual(ledger.suggestedCategory(for: "Quokka notes"), "work")
        ledger.setLogDeleted("a", deleted: true, writer: "phone")
        XCTAssertNil(ledger.suggestedCategory(for: "Quokka notes"))
        try ledger.confirmCategory(for: "a", categoryID: "rest", writer: "phone")
        XCTAssertEqual(ledger.entries.first { $0.id == "a" }?.categoryID, "work")
        ledger.setLogDeleted("a", deleted: false, writer: "phone")
        XCTAssertEqual(ledger.suggestedCategory(for: "Quokka notes"), "work")
        // Deleting its group while a sample is hidden must not restore that group on Undo.
        ledger.setLogDeleted("a", deleted: true, writer: "phone")
        try ledger.deleteCategory(id: "work", writer: "phone")
        ledger.setLogDeleted("a", deleted: false, writer: "phone")
        XCTAssertNil(ledger.confirmedCategoryID(for: try XCTUnwrap(ledger.activeEntries.first { $0.id == "a" })))
    }
    func testAllDayUsesFourUniqueHourlyRequestsAndCoversMidnight() throws {
        var settings = Settings(); settings.notificationsAllDay = true
        let schedule = try settings.notificationSchedule()
        XCTAssertEqual(schedule.count, 4)
        XCTAssertTrue(schedule.allSatisfy { $0.hour == nil })
        XCTAssertEqual(schedule.map(\.minute), [0, 15, 30, 45])
        XCTAssertEqual(Set(schedule.map(\.id)).count, 4)
        XCTAssertEqual(try settings.notificationMinutes(), Array(stride(from: 0, to: 1440, by: 15)))
        let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(try restored.notificationSchedule(), schedule)
        var window = Settings()
        XCTAssertEqual(try window.notificationSchedule().count, 61)
        window.endMinute = 23 * 60
        XCTAssertThrowsError(try window.notificationSchedule())
        let legacy = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.notificationsAllDay)
    }
    func testRankingDeletionAndUndoKeepRemainingRankedOrderAndFinishWithOneIdea() throws {
        var ledger = Ledger()
        for id in ["a", "b", "c"] { try ledger.addCapture(text: id, id: id, writer: "phone", now: now) }
        ledger.prepareRanking(writer: "phone")
        while let pair = ledger.rankingPair { ledger.chooseCapture(min(pair.first, pair.second), from: pair, writer: "phone") }
        ledger.setCaptureDeleted("b", deleted: true, writer: "phone"); ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs, ["a", "c"])
        ledger.setCaptureDeleted("b", deleted: false, writer: "phone"); ledger.replenishTopTen(writer: "phone")
        while let pair = ledger.rankingPair { ledger.chooseCapture(min(pair.first, pair.second), from: pair, writer: "phone") }
        XCTAssertEqual(ledger.rankedCaptureIDs, ["a", "b", "c"])
        ledger.setCaptureDeleted("a", deleted: true, writer: "phone")
        ledger.setCaptureDeleted("c", deleted: true, writer: "phone"); ledger.prepareRanking(writer: "phone")
        XCTAssertNil(ledger.rankingPair); XCTAssertEqual(ledger.rankedCaptureIDs, ["b"])
    }
}
