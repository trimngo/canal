import XCTest
@testable import LedgerCore

final class CalendarCategoryChoiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func event(_ id: String = "class") -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: id, calendarID: "selected", calendarName: "Classes", title: "Class",
                              start: now.addingTimeInterval(600), end: now.addingTimeInterval(1200))
    }
    func testManualChoiceReplacesLatePredictionsWithoutRecordingOrReviewingFutureTime() throws {
        var ledger = Ledger(); let snapshot = event()
        try ledger.setPlannedCalendarCategories(snapshot, categoryIDs: ["social"], writer: "phone")
        for _ in 0..<2 {
            let plan = ledger.calendarForecast([.init(snapshot: snapshot, categoryIDs: ["work"])], on: now, now: now)
            XCTAssertEqual(plan.directMinutes["social"], 10)
            XCTAssertNil(plan.directMinutes["work"])
        }
        XCTAssertTrue(ledger.entries.isEmpty)
        XCTAssertTrue(ledger.calendarEventsToReview(now: now).isEmpty)
        XCTAssertEqual(ledger.calendarEvents?.first?.decision, .pending)
        XCTAssertEqual(ledger.history(range: .today, now: now).trackedMinutes, 0)
    }
    func testExplicitUncategorizedAndResetSurviveBackupAndStaleMerge() throws {
        var ledger = Ledger(); let snapshot = event()
        try ledger.setPlannedCalendarCategories(snapshot, categoryIDs: [], writer: "phone")
        let stale = ledger
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(restored.plannedCalendarCategoryIDs(for: snapshot.id), [])
        XCTAssertEqual(restored.calendarForecast([.init(snapshot: snapshot, categoryIDs: ["work"])], on: now, now: now).directMinutes["uncategorized"], 10)
        try ledger.setPlannedCalendarCategories(snapshot, categoryIDs: nil, writer: "phone")
        ledger.merge(stale)
        XCTAssertNil(ledger.plannedCalendarCategoryIDs(for: snapshot.id))
        XCTAssertEqual(ledger.calendarForecast([.init(snapshot: snapshot, categoryIDs: ["work"])], on: now, now: now).directMinutes["work"], 10)
    }
    func testRescheduleKeepsChoiceAndConfirmationUsesOriginalPeriodOnlyAfterEnd() throws {
        var ledger = Ledger(); var snapshot = event()
        try ledger.setPlannedCalendarCategories(snapshot, categoryIDs: ["social"], writer: "phone")
        snapshot.end = now.addingTimeInterval(1800); snapshot.title = "Rescheduled class"
        ledger.collectCalendarEvents([snapshot], writer: "phone", now: now)
        XCTAssertEqual(ledger.calendarEvents?.first?.snapshot, snapshot)
        XCTAssertTrue(ledger.calendarEventsToReview(now: now.addingTimeInterval(1201)).isEmpty)
        XCTAssertThrowsError(try ledger.decideCalendarEvent(snapshot.id, confirm: true, writer: "phone", now: now))
        let ended = now.addingTimeInterval(1801)
        ledger.collectCalendarEvents([snapshot], writer: "phone", now: ended)
        XCTAssertEqual(ledger.calendarEventsToReview(now: ended).count, 1)
        try ledger.decideCalendarEvent(snapshot.id, confirm: true, writer: "phone", now: ended)
        XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertEqual(ledger.entries.first?.intervalStart, snapshot.start)
        XCTAssertEqual(ledger.entries.first?.end, snapshot.end)
        XCTAssertEqual(ledger.confirmedCategoryIDs(for: try XCTUnwrap(ledger.entries.first)), ["social"])
        XCTAssertThrowsError(try ledger.setPlannedCalendarCategories(snapshot, categoryIDs: ["work"], writer: "phone"))
    }
    func testChoicesStayWithOccurrenceAndRejectInvalidOrConflictingCategoriesAtomically() throws {
        var ledger = Ledger(); let snapshot = event()
        ledger.categories.append(.init(id: "child", name: "Child"))
        try ledger.moveCategory("child", to: "work", writer: "phone")
        let before = ledger
        XCTAssertThrowsError(try ledger.setPlannedCalendarCategories(snapshot, categoryIDs: ["missing"], writer: "phone"))
        XCTAssertThrowsError(try ledger.setPlannedCalendarCategories(snapshot, categoryIDs: ["work", "child"], writer: "phone"))
        XCTAssertEqual(ledger, before)
        try ledger.setPlannedCalendarCategories(snapshot, categoryIDs: ["child", "social"], writer: "phone")
        XCTAssertNil(ledger.plannedCalendarCategoryIDs(for: "next-occurrence"))
        XCTAssertEqual(ledger.calendarForecast([.init(snapshot: event("next-occurrence"), categoryIDs: ["work"])], on: now, now: now).directMinutes["work"], 10)
    }
    func testQuickDeliveryCarriesChoiceAndLegacyRecordDecodesWithoutIt() throws {
        var ledger = Ledger(); let snapshot = event()
        try ledger.setPlannedCalendarCategories(snapshot, categoryIDs: ["work"], writer: "phone")
        var delivery = CompanionQuickDelivery()
        let data = try XCTUnwrap(delivery.prepare(ledger, id: "choice"))
        let packet = try JSONDecoder().decode(CompanionQuickPacket.self, from: data)
        var receiver = Ledger(); receiver.merge(packet.ledger)
        XCTAssertEqual(receiver.plannedCalendarCategoryIDs(for: snapshot.id), ["work"])
        XCTAssertTrue(receiver.entries.isEmpty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try XCTUnwrap(ledger.calendarEvents?.first))) as? [String: Any])
        object.removeValue(forKey: "plannedCategoryIDs")
        let legacy = try JSONDecoder().decode(CalendarEventRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.plannedCategoryIDs)
    }
    func testDeletedCategoryStaysExplicitlyUncategorizedUntilUserChangesChoice() throws {
        var ledger = Ledger(); let snapshot = event()
        try ledger.setPlannedCalendarCategories(snapshot, categoryIDs: ["work"], writer: "phone")
        ledger.categories.removeAll { $0.id == "work" }
        XCTAssertEqual(ledger.plannedCalendarCategoryIDs(for: snapshot.id), [])
        XCTAssertEqual(ledger.calendarForecast([.init(snapshot: snapshot, categoryIDs: ["social"])], on: now, now: now).directMinutes["uncategorized"], 10)
        try ledger.decideCalendarEvent(snapshot.id, confirm: true, writer: "phone", now: snapshot.end)
        XCTAssertEqual(ledger.confirmedCategoryIDs(for: try XCTUnwrap(ledger.entries.first)), [])
    }
}
