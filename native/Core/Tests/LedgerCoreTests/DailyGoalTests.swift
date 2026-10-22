import XCTest
@testable import LedgerCore

final class DailyGoalTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!; return cal
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func fixture() throws -> Ledger {
        var ledger = Ledger()
        ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"),
                             LedgerCategory(id: "music", name: "Music"), LedgerCategory(id: "food", name: "Eating")]
        ledger.settings.reportingTimeZoneIdentifier = "Europe/Berlin"
        try ledger.moveCategory("teaching", to: "work", writer: "test")
        return ledger
    }

    func testCountdownBeforeInsideAndAfterWindowDoesNotAddPreStartHours() throws {
        let ledger = try fixture()
        for (stamp, expected) in [("2026-10-22T05:00:00+02:00", 900.0), ("2026-10-22T07:00:00+02:00", 900),
                                   ("2026-10-22T16:30:00+02:00", 330), ("2026-10-22T22:00:00+02:00", 0),
                                   ("2026-10-22T23:30:00+02:00", 0)] {
            let now = date(stamp)
            let window = try XCTUnwrap(ledger.goalDayWindow(on: now, now: now, calendar: calendar))
            XCTAssertEqual(window.minutes, 900)
            XCTAssertEqual(window.remainingMinutes, expected)
            XCTAssertEqual(window.elapsedMinutes + window.remainingMinutes, window.minutes)
        }
    }

    func testPercentageConvertsToConfiguredDayEvenWithoutHistoryAndWithoutChangingGoals() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["music": 20, "teaching": 30], effectiveAt: date("2026-01-01T00:00:00Z"), writer: "test")
        let now = date("2026-10-22T12:00:00+02:00"), budgets = ledger.targetBudgets
        let ref = ledger.goalAllocationReference(now: now, calendar: calendar)
        XCTAssertNil(ref.averageDayMinutes)
        XCTAssertEqual(ref.dailyMinutes(for: 20), 180)
        XCTAssertEqual(ref.percentage(forDailyHours: 3), 20)
        let before = try XCTUnwrap(ledger.dailyGoals(now: now, calendar: calendar))
        XCTAssertEqual(before.goals.first { $0.id == "music" }?.remainingMinutes, 180)
        XCTAssertEqual(before.neededMinutes, 450)
        ledger.settings.endMinute = 19 * 60
        let after = try XCTUnwrap(ledger.dailyGoals(now: now, calendar: calendar))
        XCTAssertEqual(after.goals.first { $0.id == "music" }?.targetMinutes, 144)
        XCTAssertEqual(ledger.currentGoals()["music"], 20)
        XCTAssertEqual(ledger.targetBudgets, budgets)
    }

    func testParentGoalsAndDirectLogsDoNotDoubleCountRequiredTime() throws {
        var ledger = try fixture()
        let now = date("2026-10-22T20:00:00+02:00")
        try ledger.saveAllocationGoals(["teaching": 10, "music": 10, "food": 0], effectiveAt: date("2026-01-01T00:00:00Z"), writer: "test")
        try ledger.saveSample(at: date("2026-10-22T09:00:00+02:00"), activity: "Direct work", categoryIDs: ["work"], writer: "test", now: now)
        try ledger.saveSample(at: date("2026-10-22T10:00:00+02:00"), activity: "Split work and music", categoryIDs: ["teaching", "music"], writer: "test", now: now)
        let report = try XCTUnwrap(ledger.dailyGoals(now: now, calendar: calendar))
        XCTAssertEqual(Set(report.goals.map(\.id)), ["work", "teaching", "music", "food"])
        XCTAssertTrue(try XCTUnwrap(report.goals.first { $0.id == "work" }).isRollup)
        XCTAssertEqual(report.commitments.reduce(0) { $0 + $1.targetMinutes }, 180)
        let actual = ledger.allocation(on: now, now: now, calendar: calendar)
        let split = actual.directMinutes["music"]!
        XCTAssertEqual(report.goals.first { $0.id == "teaching" }?.actualMinutes, split)
        XCTAssertEqual(report.goals.first { $0.id == "music" }?.actualMinutes, split)
        XCTAssertEqual(report.neededMinutes, 180 - 2 * split, accuracy: 0.00001)
        XCTAssertGreaterThan(actual.total(for: "work", ledger: ledger), split)
    }

    func testEarlyAndLateLogsCountForBothEstimationMethodsWithoutClipping() throws {
        for method in InferenceMethod.allCases {
            var ledger = try fixture(); ledger.settings.inferenceMethod = method
            let now = date("2026-10-22T23:45:00+02:00")
            try ledger.saveAllocationGoals(["music": 25], effectiveAt: date("2026-01-01T00:00:00Z"), writer: "test")
            try ledger.saveSample(at: date("2026-10-22T02:00:00+02:00"), activity: "Early music", categoryIDs: ["music"], writer: "test", now: now)
            try ledger.saveSample(at: date("2026-10-22T23:00:00+02:00"), activity: "Late music", categoryIDs: ["music"], writer: "test", now: now)
            let entries = ledger.entries
            let report = try XCTUnwrap(ledger.dailyGoals(now: now, calendar: calendar))
            XCTAssertEqual(report.goals[0].actualMinutes, 21 * 60 + 15)
            XCTAssertEqual(report.goals[0].fraction, 1)
            XCTAssertTrue(report.goals[0].isMet)
            XCTAssertEqual(report.neededMinutes, 0)
            XCTAssertEqual(report.window.remainingMinutes, 0)
            XCTAssertEqual(ledger.entries, entries)
        }
    }

    func testShortfallAndOtherTimeUseSameScaleAndMetGoalsCannotCreateExtraRoom() throws {
        var ledger = try fixture()
        let now = date("2026-10-22T21:00:00+02:00")
        try ledger.saveAllocationGoals(["music": 20, "teaching": 30], effectiveAt: date("2026-01-01T00:00:00Z"), writer: "test")
        var report = try XCTUnwrap(ledger.dailyGoals(now: now, calendar: calendar))
        XCTAssertEqual(report.neededMinutes, 450)
        XCTAssertEqual(report.window.remainingMinutes, 60)
        XCTAssertEqual(report.shortfallMinutes, 390)
        XCTAssertEqual(report.otherMinutes, 0)
        XCTAssertEqual(report.dayBarSegments.reduce(0) { $0 + $1.minutes }, report.window.minutes)
        try ledger.saveSample(at: date("2026-10-22T08:00:00+02:00"), activity: "Music", categoryIDs: ["music"], writer: "test", now: now)
        try ledger.saveSample(at: date("2026-10-22T20:00:00+02:00"), activity: "Teaching", categoryIDs: ["teaching"], writer: "test", now: now)
        report = try XCTUnwrap(ledger.dailyGoals(now: now, calendar: calendar))
        XCTAssertEqual(report.neededMinutes, 0)
        XCTAssertEqual(report.otherMinutes, 60)
        XCTAssertEqual(report.shortfallMinutes, 0)
        XCTAssertEqual(report.dayBarSegments.reduce(0) { $0 + $1.minutes }, report.window.minutes)
    }

    func testUncategorizedTimeIsReportedAndNotInventedAsGoalProgress() throws {
        var ledger = try fixture()
        let now = date("2026-10-22T12:00:00+02:00")
        try ledger.saveAllocationGoals(["music": 20], effectiveAt: date("2026-01-01T00:00:00Z"), writer: "test")
        try ledger.saveSample(at: now.addingTimeInterval(-3600), activity: "Unreviewed", categoryID: nil, writer: "test", now: now)
        let report = try XCTUnwrap(ledger.dailyGoals(now: now, calendar: calendar))
        XCTAssertEqual(report.uncategorizedMinutes, 15)
        XCTAssertEqual(report.goals[0].actualMinutes, 0)
        XCTAssertEqual(report.goals[0].remainingMinutes, 180)
    }

    func testDayWindowUsesReportingZoneAndDSTElapsedTime() throws {
        var ledger = try fixture()
        ledger.settings.startMinute = 60; ledger.settings.endMinute = 4 * 60
        for (stamp, length, remaining) in [("2026-03-29T03:00:00+02:00", 120.0, 60.0),
                                          ("2026-10-25T02:30:00+02:00", 240, 150),
                                          ("2026-10-25T02:30:00+01:00", 240, 90)] {
            let now = date(stamp)
            var utc = calendar; utc.timeZone = TimeZone(secondsFromGMT: 0)!
            let window = try XCTUnwrap(ledger.goalDayWindow(on: now, now: now, calendar: utc))
            XCTAssertEqual(window.minutes, length)
            XCTAssertEqual(window.remainingMinutes, remaining)
        }
        ledger.settings.startMinute = 150 // Missing 02:30 on the spring-forward date.
        let now = date("2026-03-29T03:15:00+02:00")
        let window = try XCTUnwrap(ledger.goalDayWindow(on: now, now: now, calendar: calendar))
        XCTAssertEqual(calendar.component(.hour, from: window.interval.start), 3)
        XCTAssertEqual(window.remainingMinutes, 45)
    }

    func testAllDayAlertsAndDisabledAlertsDoNotChangeGoalWindow() throws {
        var ledger = try fixture()
        let now = date("2026-10-22T12:00:00+02:00")
        let before = ledger.goalDayWindow(on: now, now: now, calendar: calendar)
        ledger.settings.notificationsAllDay = true; ledger.settings.notificationsEnabled = true
        XCTAssertEqual(ledger.goalDayWindow(on: now, now: now, calendar: calendar), before)
        ledger.settings.startMinute = -15
        XCTAssertNil(ledger.dailyGoals(now: now, calendar: calendar))
    }

    func testBackupAndSettingsMergeKeepWindowGoalsAndRawSamples() throws {
        var ledger = try fixture()
        let now = date("2026-10-22T12:00:00+02:00")
        try ledger.saveSample(at: date("2026-10-22T03:00:00+02:00"), activity: "Outside window", categoryIDs: ["music"], writer: "watch", now: now)
        try ledger.saveAllocationGoals(["music": 25], effectiveAt: date("2026-01-01T00:00:00Z"), writer: "phone")
        var watch = ledger, settings = ledger.settings
        settings.startMinute = 8 * 60; settings.endMinute = 21 * 60
        try watch.saveSettings(settings, writer: "watch")
        ledger.merge(watch)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(restored.entries, watch.entries)
        XCTAssertEqual(restored.dailyGoals(now: now, calendar: calendar), watch.dailyGoals(now: now, calendar: calendar))
        XCTAssertEqual(restored.goalAllocationReference(now: now, calendar: calendar).dailyMinutes(for: 25), 195)
    }

    func testGoalWidthsAreProportionalAndProgressLivesInsideTheTarget() throws {
        var ledger = try fixture()
        let now = date("2026-10-22T17:30:00+02:00")
        try ledger.saveAllocationGoals(["music": 10, "teaching": 20], effectiveAt: date("2026-01-01T00:00:00Z"), writer: "test")
        let report = try XCTUnwrap(ledger.dailyGoals(now: now, calendar: calendar))
        let music = try XCTUnwrap(report.goals.first { $0.id == "music" })
        let teaching = try XCTUnwrap(report.goals.first { $0.id == "teaching" })
        XCTAssertEqual(report.goalWidthFraction(teaching), 2 * report.goalWidthFraction(music))
        XCTAssertEqual(teaching.fraction, 0)
        XCTAssertEqual(report.goalWidthFraction(teaching) * teaching.fraction, 0)
        XCTAssertEqual(teaching.targetMinutes, 180)
        XCTAssertEqual(music.targetMinutes, 90)
    }

    func testVisibleLeafGoalsSetTheBarScaleWithoutParentTotals() throws {
        var ledger = try fixture()
        var admin = LedgerCategory(id: "admin", name: "Administration"); admin.parentID = "work"
        ledger.categories.append(admin)
        try ledger.saveAllocationGoals(["music": 10, "teaching": 20, "admin": 15], effectiveAt: date("2026-01-01T00:00:00Z"), writer: "test")
        let report = try XCTUnwrap(ledger.dailyGoals(now: date("2026-10-22T17:30:00+02:00"), calendar: calendar))
        XCTAssertEqual(Set(report.commitments.map(\.id)), ["music", "teaching", "admin"])
        XCTAssertEqual(report.goals.first { $0.id == "work" }?.targetMinutes, 315)
        XCTAssertEqual(report.goalScaleMinutes, 180)
        XCTAssertEqual(report.neededMinutes, 405)
        XCTAssertEqual(report.goalWidthFraction(try XCTUnwrap(report.commitments.first { $0.id == "teaching" })), 1)
    }

    func testWholeDayBarIncludesElapsedGoalsAndOtherWithoutChangingScale() throws {
        var ledger = try fixture()
        let now = date("2026-10-22T17:30:00+02:00")
        try ledger.saveAllocationGoals(["music": 10, "teaching": 10], effectiveAt: date("2026-01-01T00:00:00Z"), writer: "test")
        let report = try XCTUnwrap(ledger.dailyGoals(now: now, calendar: calendar))
        XCTAssertEqual(report.dayBarSegments.first?.kind, .elapsed)
        XCTAssertEqual(report.dayBarSegments.first?.minutes, 630)
        XCTAssertEqual(report.dayBarSegments.filter { if case .goal = $0.kind { return true }; return false }.reduce(0) { $0 + $1.minutes }, 180)
        XCTAssertEqual(report.dayBarSegments.last?.kind, .other)
        XCTAssertEqual(report.dayBarSegments.last?.minutes, 90)
        XCTAssertEqual(report.dayBarSegments.reduce(0) { $0 + $1.minutes }, 900)
        XCTAssertEqual(report.shortfallMinutes, 0)
    }

    func testOverflowNeverShrinksElapsedTimeOrPretendsGoalsFit() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["music": 50, "teaching": 50], effectiveAt: date("2026-01-01T00:00:00Z"), writer: "test")
        let now = date("2026-10-22T21:00:00+02:00")
        let report = try XCTUnwrap(ledger.dailyGoals(now: now, calendar: calendar))
        XCTAssertEqual(report.dayBarSegments.first?.minutes, 840)
        XCTAssertEqual(report.dayBarSegments.reduce(0) { $0 + $1.minutes }, 900)
        XCTAssertEqual(report.shortfallMinutes, 840)
        XCTAssertFalse(report.dayBarSegments.contains { $0.kind == .other })
        XCTAssertEqual(report.commitments.reduce(0) { $0 + $1.remainingMinutes }, 900)
    }

    func testCompletedZeroAndParentGoalsStayVisibleButBlankGoalsDoNot() throws {
        var ledger = try fixture()
        try ledger.saveAllocationGoals(["music": 0, "teaching": 1], effectiveAt: date("2026-01-01T00:00:00Z"), writer: "test")
        let now = date("2026-10-22T17:30:00+02:00")
        try ledger.saveSample(at: now.addingTimeInterval(-3600), activity: "Teaching", categoryIDs: ["teaching"], writer: "test", now: now)
        let report = try XCTUnwrap(ledger.dailyGoals(now: now, calendar: calendar))
        XCTAssertEqual(Set(report.goals.map(\.id)), ["work", "teaching", "music"])
        XCTAssertTrue(report.goals.allSatisfy(\.isMet))
        XCTAssertEqual(report.goals.first { $0.id == "teaching" }?.depth, 1)
        XCTAssertEqual(report.goalWidthFraction(try XCTUnwrap(report.goals.first { $0.id == "music" })), 0)
        XCTAssertEqual(report.neededMinutes, 0)
        XCTAssertEqual(report.dayBarSegments.last?.kind, .other)
    }
}
