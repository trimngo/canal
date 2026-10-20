import XCTest
@testable import LedgerCore

final class NotificationTimingTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Europe/Berlin")!; return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private var now: Date { date("2026-10-20T10:00:00Z") }
    private func randomized() -> Settings {
        var value = Settings(); value.notificationTiming = .randomized; value.notificationsAllDay = true
        return value
    }

    func testLegacySettingsKeepRegularFifteenMinutePrompts() throws {
        let value = try JSONDecoder().decode(Settings.self, from: Data("{\"notificationsEnabled\":true,\"startMinute\":420,\"endMinute\":1320}".utf8))
        XCTAssertEqual(value.notificationTiming, .regular)
        XCTAssertEqual(value.notificationDelivery, .automatic)
        XCTAssertEqual(value.regularNotificationInterval, 15)
        XCTAssertEqual(value.randomizedNotificationInterval, 15)
        XCTAssertEqual(try value.notificationSchedule().count, 61)
        XCTAssertFalse(value.usesQueuedNotifications)
    }

    func testRegularIntervalsStayEvenAndAllDayRepeatsStayUnderTheLimit() throws {
        var value = Settings(); value.notificationsAllDay = true
        for interval in NotificationTiming.intervals {
            value.regularNotificationInterval = interval
            let minutes = try value.notificationMinutes(), schedule = try value.notificationSchedule()
            XCTAssertTrue(schedule.count <= 60)
            XCTAssertEqual(Set(schedule.map(\.id)).count, schedule.count)
            XCTAssertEqual(minutes.first, 0)
            XCTAssertTrue(zip(minutes, minutes.dropFirst()).allSatisfy { $1 - $0 == interval })
            XCTAssertEqual(try value.notificationDates(after: now, count: 30, calendar: calendar).count, 30)
        }
        value.notificationsAllDay = false; value.regularNotificationInterval = 5
        XCTAssertTrue(value.usesQueuedNotifications)
        let dates = try value.notificationQueue(existing: [], now: now, capacity: 60, calendar: calendar)
        XCTAssertEqual(dates.count, 60)
        XCTAssertEqual(dates[1].timeIntervalSince(dates[0]), 300)
    }

    func testRandomGapsHaveRequestedBoundsAndMeanWithoutClockAlignment() throws {
        var value = randomized()
        for interval in [5, 15, 45, 120] {
            value.randomizedNotificationInterval = interval
            var index = 0
            let dates = try value.notificationDates(after: now, count: 1000, calendar: calendar, random: {
                defer { index += 1 }; return Double(index % 101) / 100
            })
            let gaps = zip([now] + dates.dropLast(), dates).map { $1.timeIntervalSince($0) / 60 }
            XCTAssertGreaterThanOrEqual(gaps.min()!, Double(interval) * 2 / 3 - 0.001)
            XCTAssertLessThanOrEqual(gaps.max()!, Double(interval) * 4 / 3 + 0.001)
            XCTAssertEqual(gaps.reduce(0, +) / Double(gaps.count), Double(interval), accuracy: Double(interval) * 0.01)
            XCTAssertGreaterThan(Set(gaps.map { Int(($0 * 60).rounded()) }).count, 50)
        }
    }

    func testRefillKeepsFutureTimesAndExtendsFromLastInsteadOfResettingFromNow() throws {
        let value = randomized()
        let initial = try value.notificationQueue(existing: [], now: now, calendar: calendar, random: { 0.5 })
        XCTAssertEqual(initial.count, 60)
        let later = now.addingTimeInterval(20 * 60)
        let next = try value.notificationQueue(existing: initial + [initial[1]], now: later, calendar: calendar, random: { 0.5 })
        XCTAssertEqual(next.count, 60)
        XCTAssertEqual(Array(next.prefix(59)), Array(initial.dropFirst()))
        XCTAssertEqual(next.last!.timeIntervalSince(initial.last!), 900)
        XCTAssertEqual(try value.notificationQueue(existing: next, now: later, calendar: calendar, random: { 0 }), next)
        XCTAssertEqual(try value.notificationQueue(existing: [], now: now, capacity: 4, calendar: calendar).count, 4)
        XCTAssertTrue(try value.notificationQueue(existing: [], now: now, capacity: 0).isEmpty)
    }

    func testRandomWindowSkipsQuietHoursAndNeverSchedulesPastStop() throws {
        var value = randomized(); value.notificationsAllDay = false
        let dates = try value.notificationDates(after: date("2026-10-20T19:50:00Z"), count: 150, calendar: calendar, random: { 1 })
        XCTAssertEqual(dates.first, date("2026-10-21T05:20:00Z"))
        XCTAssertTrue(dates.allSatisfy {
            let c = calendar.dateComponents([.hour, .minute, .second], from: $0)
            let minute = c.hour! * 60 + c.minute!
            return minute >= value.startMinute && minute <= value.endMinute
        })
        XCTAssertEqual(Set(dates).count, dates.count)
    }

    func testShortWindowGetsAContainedSampleEvenWhenAverageGapIsLonger() throws {
        var value = randomized(); value.notificationsAllDay = false
        value.startMinute = 420; value.endMinute = 435; value.randomizedNotificationInterval = 120
        let dates = try value.notificationDates(after: now, count: 10, calendar: calendar, random: { 0.5 })
        XCTAssertEqual(dates.count, 10)
        for time in dates {
            XCTAssertEqual(calendar.component(.hour, from: time), 7)
            XCTAssertLessThan(calendar.component(.minute, from: time), 15)
        }
    }

    func testDSTAndTimeZonesKeepAbsoluteRandomGapsAndLocalWindows() throws {
        var value = randomized()
        for transition in ["2026-03-29T00:55:00Z", "2026-10-25T00:55:00Z"] {
            let start = date(transition)
            let dates = try value.notificationDates(after: start, count: 120, calendar: calendar, random: { 0.5 })
            XCTAssertTrue(zip([start] + dates.dropLast(), dates).allSatisfy { $1.timeIntervalSince($0) == 900 })
            value.notificationsAllDay = false; value.startMinute = 2 * 60 + 15; value.endMinute = 2 * 60 + 45
            let window = try value.notificationDates(after: start, count: 10, calendar: calendar, random: { 0.5 })
            XCTAssertTrue(window.allSatisfy { calendar.component(.hour, from: $0) == 2 })
            XCTAssertTrue(zip([start] + window.dropLast(), window).allSatisfy { $1 > $0 })
            value.notificationsAllDay = true
        }
        value.notificationsAllDay = false
        var tokyo = calendar; tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let dates = try value.notificationDates(after: now, count: 10, calendar: tokyo, random: { 0.5 })
        XCTAssertTrue(dates.allSatisfy { tokyo.component(.hour, from: $0) == 2 })
    }

    func testInvalidIntervalsAndWindowsAreRejectedBeforeChangingSavedSettings() throws {
        var ledger = Ledger(), value = Settings()
        for interval in [0, -15, 1, 17, Int.max] {
            value.regularNotificationInterval = interval
            XCTAssertThrowsError(try ledger.saveSettings(value, writer: "phone"))
        }
        value = Settings(); value.randomizedNotificationInterval = 0
        XCTAssertThrowsError(try ledger.saveSettings(value, writer: "phone"))
        value = Settings(); value.endMinute = value.startMinute
        XCTAssertThrowsError(try ledger.saveSettings(value, writer: "phone"))
        XCTAssertEqual(ledger.settings, Settings())
    }

    func testBothModesRememberTheirIntervalAcrossBackupAndPhoneWatchMerge() throws {
        var phone = Ledger(), watch = phone, settings = phone.settings
        settings.notificationsEnabled = true; settings.notificationTiming = .randomized
        settings.notificationDelivery = .watch
        settings.regularNotificationInterval = 30; settings.randomizedNotificationInterval = 20
        try phone.saveSettings(settings, writer: "phone")
        watch.merge(phone)
        XCTAssertEqual(watch.settings, phone.settings)
        let backup = try LedgerBackup.decode(LedgerBackup(ledger: watch).encoded()).ledger
        XCTAssertEqual(backup.settings, phone.settings)
        settings = watch.settings; settings.notificationTiming = .regular
        try watch.saveSettings(settings, writer: "watch"); phone.merge(watch)
        XCTAssertEqual(phone.settings.regularNotificationInterval, 30)
        XCTAssertEqual(phone.settings.randomizedNotificationInterval, 20)
        XCTAssertEqual(phone.settings.notificationTiming, .regular)
        XCTAssertEqual(phone.settings.notificationDelivery, .watch)
    }

    func testWatchDeliveryOwnsOnlyOneLocalScheduleAndAutomaticPreservesPhoneRouting() {
        XCTAssertTrue(NotificationDelivery.watch.schedulesLocally(onWatch: true))
        XCTAssertFalse(NotificationDelivery.watch.schedulesLocally(onWatch: false))
        XCTAssertTrue(NotificationDelivery.automatic.schedulesLocally(onWatch: false))
        XCTAssertFalse(NotificationDelivery.automatic.schedulesLocally(onWatch: true))
    }
}
