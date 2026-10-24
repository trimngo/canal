import XCTest
@testable import LedgerCore

final class FeedbackReviewTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private var now: Date { date("2026-10-24T15:00:00Z") }
    private func ledger() -> Ledger {
        var value = Ledger()
        value.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "digs", name: "DIGS"), LedgerCategory(id: "music", name: "Music")]
        value.settings.reportingTimeZoneIdentifier = "UTC"
        return value
    }
    func testCustomAcronymAndExactMultiLabelChoicesExplainTheirEvidence() throws {
        var value = ledger()
        try value.saveSample(id: "confirmed", at: now.addingTimeInterval(-1000), activity: "Rehearsing public song", categoryIDs: ["digs", "music"], writer: "p", now: now)
        let model = OfflineCategoryModel(ledger: value)
        XCTAssertEqual(model.suggest("Prepare DIGS lecture")?.categoryIDs, ["digs"])
        XCTAssertEqual(model.suggest("Prepare DIGS lecture")?.reason, "Matched DIGS")
        XCTAssertEqual(model.suggest("rehearsing PUBLIC song!")?.categoryIDs, ["digs", "music"])
        XCTAssertNil(model.suggest("Thinking about things"))
    }
    func testConfirmedVocabularyAndAmbiguity() throws {
        var value = ledger()
        try value.saveSample(at: now, activity: "Lecture slides assessment", categoryIDs: ["digs"], writer: "p", now: now)
        XCTAssertEqual(OfflineCategoryModel(ledger: value).suggest("Review lecture slides")?.categoryIDs, ["digs"])
        try value.saveSample(at: now, activity: "Lecture slides assessment", categoryIDs: ["music"], writer: "p", now: now)
        XCTAssertNil(OfflineCategoryModel(ledger: value).suggest("Lecture slides assessment"))
        XCTAssertNil(OfflineCategoryModel(ledger: value).suggest("Review lecture slides"))
    }
    func testSemanticEvidenceRequiresStrongUniqueMatch() {
        let model = OfflineCategoryModel(ledger: ledger())
        XCTAssertEqual(model.suggest("rehearsal", semantic: [.init(categoryIDs: ["music"], similarity: 0.93), .init(categoryIDs: ["digs"], similarity: 0.65)])?.reason, "Similar to confirmed entries")
        XCTAssertNil(model.suggest("rehearsal", semantic: [.init(categoryIDs: ["music"], similarity: 0.90), .init(categoryIDs: ["digs"], similarity: 0.86)]))
        XCTAssertNil(model.suggest("rehearsal", semantic: [.init(categoryIDs: ["music"], similarity: 0.7)]))
    }
    func testSuggestedSharesCountOnceRollUpAndRemainUnreviewed() throws {
        var value = ledger(); try value.moveCategory("digs", to: "work", writer: "p")
        let time = date("2026-10-23T10:00:00Z")
        try value.saveSample(id: "sample", at: time, activity: "Preparing lecture", categoryIDs: [], writer: "p", now: now)
        let suggestion = CategorySuggestion(categoryIDs: ["digs", "music"], reason: "Confirmed vocabulary", sourceText: "Preparing lecture")
        try value.suggestCategories(suggestion, logID: "sample", writer: "p")
        let entry = try XCTUnwrap(value.activeEntries.first)
        XCTAssertTrue(value.needsCategoryReview(entry)); XCTAssertTrue(value.confirmedCategoryIDs(for: entry).isEmpty)
        let period = value.allocation(on: time, now: now, calendar: cal)
        XCTAssertEqual(period.trackedMinutes, 15)
        XCTAssertEqual(period.directMinutes["digs"], 7.5); XCTAssertEqual(period.directMinutes["music"], 7.5)
        XCTAssertEqual(period.unreviewed(for: "work", ledger: value), 7.5)
        XCTAssertEqual(period.unreviewedDirectMinutes.values.reduce(0,+), 15)
        let report = value.history(range: .week, now: now, calendar: cal)
        XCTAssertEqual(report.unreviewed(for: "work", in: value), 7.5)
        try value.confirmCategories(for: "sample", categoryIDs: ["music"], writer: "p")
        let confirmed = value.allocation(on: time, now: now, calendar: cal)
        XCTAssertTrue(confirmed.unreviewedDirectMinutes.isEmpty)
        XCTAssertEqual(confirmed.directMinutes["music"], 15)
        XCTAssertFalse(value.needsCategoryReview(value.activeEntries[0]))
    }
    func testAutomaticGuessesNeverTrainAndManualChoicesCannotBeOverwritten() throws {
        var value = ledger()
        try value.saveSample(id: "s", at: now, activity: "Preparing lecture slides", categoryIDs: [], writer: "p", now: now)
        let guess = CategorySuggestion(categoryIDs: ["digs"], reason: "Matched DIGS", sourceText: "Preparing lecture slides")
        try value.suggestCategories(guess, logID: "s", writer: "p")
        XCTAssertTrue(OfflineCategoryModel(ledger: value).examples.isEmpty)
        try value.confirmCategories(for: "s", categoryIDs: [], writer: "p")
        try value.suggestCategories(guess, logID: "s", writer: "p")
        XCTAssertNil(value.activeEntries[0].categorySuggestion)
        XCTAssertTrue(value.effectiveCategoryIDs(for: value.activeEntries[0]).isEmpty)
    }
    func testSuggestionsSurviveBackupMergeAndLegacyCleanup() throws {
        var value = ledger()
        try value.saveSample(id: "s", at: now, activity: "DIGS", categoryIDs: [], writer: "p", now: now)
        try value.suggestCategories(CategorySuggestion(categoryIDs: ["digs"], reason: "Matched DIGS", sourceText: "DIGS"), logID: "s", writer: "p")
        let idea = try value.addCapture(text: "DIGS lecture", writer: "p", now: now)
        try value.suggestCategories(CategorySuggestion(categoryIDs: ["digs"], reason: "Matched DIGS", sourceText: idea.text), captureID: idea.id, writer: "p")
        var copy = try LedgerBackup.decode(LedgerBackup(ledger: value).encoded()).ledger
        copy.prepareGroupSuggestions(writer: "old-watch")
        XCTAssertEqual(copy, value)
        var remote = ledger(); remote.merge(copy); copy.merge(remote)
        XCTAssertEqual(copy, remote)
        XCTAssertEqual(copy.inboxCategorizationIDs(uncategorizedOnly: true), [idea.id])
        try copy.categorizeCapture(id: idea.id, categoryIDs: ["digs"], writer: "p")
        XCTAssertNil(copy.captures.first?.categorySuggestion)
        XCTAssertTrue(copy.inboxCategorizationIDs(uncategorizedOnly: true).isEmpty)
    }
    func testLegacyAutomaticCacheDoesNotBecomeAcceptedTimeAndStaleGuessIsIgnored() throws {
        var value = ledger()
        value.entries = [CheckIn(end: now.addingTimeInterval(-1000), activity: "Old cached label", categoryID: "work", revision: Revision(), sampleID: "old", categoryAssignment: .automatic)]
        XCTAssertEqual(value.allocation(on: now, now: now, calendar: cal).directMinutes["uncategorized"], 15)
        try value.suggestCategories(CategorySuggestion(categoryIDs: ["digs"], reason: "Matched", sourceText: "Different text"), logID: "old", writer: "p")
        XCTAssertNil(value.entries[0].categorySuggestion)
    }
    func testEditingWordsInvalidatesGuessesButNotManualCategories() throws {
        var value = ledger()
        try value.saveSample(id: "s", at: now, activity: "DIGS", categoryIDs: [], writer: "p", now: now)
        try value.suggestCategories(CategorySuggestion(categoryIDs: ["digs"], reason: "Matched", sourceText: "DIGS"), logID: "s", writer: "p")
        try value.updateLogActivity(id: "s", activity: "New activity", writer: "p")
        XCTAssertTrue(value.effectiveCategoryIDs(for: value.entries[0]).isEmpty)
        try value.confirmCategories(for: "s", categoryIDs: ["music"], writer: "p")
        try value.updateLogActivity(id: "s", activity: "Edited manually", writer: "p")
        XCTAssertEqual(value.effectiveCategoryIDs(for: value.entries[0]), ["music"])
    }
    func testOneDayComparisonUsesOwnPriorSevenDaysAndExcludesToday() throws {
        var value = ledger()
        for day in 16 ... 24 {
            let timestamp = date("2026-10-\(day)T10:00:00Z")
            try value.saveSample(at: timestamp, activity: "sample", categoryIDs: [day == 24 ? "music" : "digs"], writer: "p", now: now)
        }
        let today = value.dailyComparison(on: now, now: now, calendar: cal)
        XCTAssertEqual(today.baselineStart, date("2026-10-17T00:00:00Z"))
        XCTAssertEqual(today.baselineEnd, date("2026-10-23T00:00:00Z"))
        XCTAssertEqual(today.representedDays, 7); XCTAssertTrue(today.isToday)
        XCTAssertEqual(today.rows.first(where: { $0.id == "digs" })?.averagePercent, 100)
        let yesterday = value.dailyComparison(on: date("2026-10-23T12:00:00Z"), now: now, calendar: cal)
        XCTAssertEqual(yesterday.baselineStart, date("2026-10-16T00:00:00Z"))
        XCTAssertEqual(yesterday.baselineEnd, date("2026-10-22T00:00:00Z"))
        XCTAssertFalse(yesterday.isToday)
    }
    func testMissingDatesExcludedButCategoryZerosCountAndDailyPercentIsArithmeticMean() throws {
        var value = ledger(); value.settings.inferenceMethod = .carryForward
        try value.saveSample(at: date("2026-10-22T10:00:00Z"), activity: "One", categoryIDs: ["work"], writer: "p", now: now)
        try value.saveSample(at: date("2026-10-23T10:00:00Z"), activity: "Two", categoryIDs: ["music"], writer: "p", now: now)
        try value.saveSample(at: date("2026-10-23T11:00:00Z"), activity: "Three", categoryIDs: ["work"], writer: "p", now: now)
        let report = value.dailyComparison(on: now, now: now, calendar: cal)
        XCTAssertFalse(report.hasData); XCTAssertEqual(report.representedDays, 2)
        let work = try XCTUnwrap(report.rows.first { $0.id == "work" })
        XCTAssertEqual(work.averagePercent, 55, accuracy: 0.001)
        XCTAssertEqual(work.averageMinutes, 11.25, accuracy: 0.001)
        XCTAssertEqual(report.rows.first(where: { $0.id == "music" })?.averagePercent, 45)
    }
    func testCalendarFirstPointCutsAllOverlappingEventsIncludingStillMeetingAndLateSync() throws {
        var value = ledger()
        let start = date("2026-10-23T10:00:00Z"), end = date("2026-10-23T11:00:00Z")
        let snapshot = CalendarEventSnapshot(id: "event", calendarID: "c", calendarName: "Meetings", title: "Meeting", start: start, end: end)
        value.collectCalendarEvents([snapshot], writer: "p", now: now)
        try value.decideCalendarEvent(snapshot.id, confirm: true, categoryIDs: ["work"], writer: "p", now: now)
        XCTAssertEqual(value.allocation(on: start, now: now, calendar: cal).trackedMinutes, 60)
        let point = date("2026-10-23T10:30:00Z")
        try value.saveSample(id: "late", at: point, activity: "Still in meeting", categoryIDs: ["work"], writer: "watch", now: now)
        XCTAssertEqual(value.calendarEventEnd(snapshot), point)
        XCTAssertEqual(value.entries.first(where: { $0.id == "calendar-event" })?.end, end)
        XCTAssertEqual(value.calendarEvents?.first?.snapshot, snapshot)
        let pieces = value.inferredSegments(on: start, now: now, calendar: cal)
        XCTAssertEqual(pieces.filter { $0.sampleID == "calendar-event" }.reduce(0) { $0 + $1.minutes }, 30)
        XCTAssertEqual(value.allocation(on: start, now: now, calendar: cal).trackedMinutes, 37.5)
        value.setLogDeleted("late", deleted: true, writer: "p")
        XCTAssertEqual(value.calendarEventEnd(snapshot), end)
        XCTAssertEqual(value.allocation(on: start, now: now, calendar: cal).trackedMinutes, 60)
    }
    func testPointAtEventStartPreventsZeroOrNegativeIntervalAndDoesNotDoubleCount() throws {
        var value = ledger(); let start = date("2026-10-23T10:00:00Z")
        let event = CalendarEventSnapshot(id: "e", calendarID: "c", calendarName: "C", title: "Event", start: start, end: start.addingTimeInterval(3600))
        value.collectCalendarEvents([event], writer: "p", now: now)
        try value.saveSample(at: start, activity: "Walking", categoryIDs: ["music"], writer: "p", now: now)
        try value.decideCalendarEvent(event.id, confirm: true, categoryIDs: ["work"], writer: "p", now: now)
        XCTAssertEqual(value.calendarEventEnd(event), start)
        XCTAssertEqual(value.allocation(on: start, now: now, calendar: cal).trackedMinutes, 15)
        XCTAssertTrue(value.inferredSegments(on: start, now: now, calendar: cal).allSatisfy { $0.end > $0.start })
    }
}
