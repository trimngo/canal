import XCTest
@testable import LedgerCore

final class SampleBoundaryTests: XCTestCase {
    private var utc: Calendar { var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!; return cal }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testBothMethodsUseHalfTheSelectedNotificationIntervalAtEachEdge() throws {
        let first = date("2026-10-20T09:00:00Z"), last = date("2026-10-20T10:00:00Z"), now = date("2026-10-21T12:00:00Z")
        for timing in NotificationTiming.allCases {
            for minutes in NotificationTiming.intervals {
                for method in InferenceMethod.allCases {
                    var ledger = Ledger()
                    ledger.settings.notificationTiming = timing
                    ledger.settings.regularNotificationInterval = timing == .regular ? minutes : 120
                    ledger.settings.randomizedNotificationInterval = timing == .randomized ? minutes : 5
                    ledger.settings.inferenceMethod = method
                    try ledger.saveSample(id: "first", at: first, activity: "Work", categoryID: "work", writer: "phone", now: now)
                    try ledger.saveSample(id: "last", at: last, activity: "Music", categoryID: "leisure", writer: "phone", now: now)
                    let original = ledger.entries, segments = ledger.inferredSegments(on: first, now: now, calendar: utc)
                    XCTAssertEqual(segments.first?.start, first.addingTimeInterval(-Double(minutes) * 30))
                    XCTAssertEqual(segments.last?.end, last.addingTimeInterval(Double(minutes) * 30))
                    XCTAssertEqual(segments[0].end, method == .midpoint ? first.addingTimeInterval(1800) : last)
                    XCTAssertEqual(segments[0].end, segments[1].start)
                    XCTAssertEqual(ledger.allocation(on: first, now: now, calendar: utc).trackedMinutes, Double(60 + minutes))
                    XCTAssertEqual(ledger.entries, original)
                }
            }
        }
    }

    func testSingleSampleIsOneMeanIntervalAndTodayNeverUsesFutureTime() throws {
        let stamp = date("2026-10-20T09:00:00Z")
        var ledger = Ledger(); ledger.settings.notificationTiming = .randomized; ledger.settings.randomizedNotificationInterval = 30
        try ledger.saveQuickSample(id: "sample", at: stamp, activity: "Observation", writer: "watch", now: stamp)
        XCTAssertEqual(ledger.allocation(on: stamp, now: stamp, calendar: utc).trackedMinutes, 15)
        XCTAssertEqual(ledger.allocation(on: stamp, now: stamp.addingTimeInterval(300), calendar: utc).trackedMinutes, 20)
        XCTAssertEqual(ledger.allocation(on: stamp, now: stamp.addingTimeInterval(86400), calendar: utc).trackedMinutes, 30)
        let raw = ledger.entries
        try ledger.saveSample(id: "later", at: stamp.addingTimeInterval(3600), activity: "Later", categoryID: nil, writer: "phone", now: stamp.addingTimeInterval(7200))
        XCTAssertEqual(ledger.allocation(on: stamp, now: stamp.addingTimeInterval(86400), calendar: utc).trackedMinutes, 90)
        XCTAssertEqual(ledger.entries.first { $0.id == "sample" }, raw.first)
    }

    func testDayBoundaryClipsPaddingAndNeverCreatesDataOnAdjacentDay() throws {
        let midnight = date("2026-10-20T00:00:00Z"), now = midnight.addingTimeInterval(86400)
        var ledger = Ledger(); ledger.settings.regularNotificationInterval = 60
        try ledger.saveSample(at: midnight.addingTimeInterval(60), activity: "Early", categoryID: nil, writer: "test", now: now)
        try ledger.saveSample(at: now.addingTimeInterval(-60), activity: "Late", categoryID: nil, writer: "test", now: now)
        let segments = ledger.inferredSegments(on: midnight, now: now, calendar: utc)
        XCTAssertEqual(segments.first?.start, midnight); XCTAssertEqual(segments.last?.end, now)
        XCTAssertEqual(ledger.allocation(on: midnight, now: now, calendar: utc).trackedMinutes, 1440)
        XCTAssertFalse(ledger.allocation(on: now, now: now.addingTimeInterval(3600), calendar: utc).sufficient)
        XCTAssertFalse(ledger.allocation(on: midnight.addingTimeInterval(-86400), now: now, calendar: utc).sufficient)
    }

    func testPaddingUsesElapsedSecondsAcrossBothDSTChanges() throws {
        for stamp in ["2026-03-29T01:00:00Z", "2026-10-25T01:00:00Z"] {
            let sample = date(stamp), now = sample.addingTimeInterval(7200)
            var ledger = Ledger(); ledger.settings.reportingTimeZoneIdentifier = "Europe/Berlin"
            ledger.settings.randomizedNotificationInterval = 60; ledger.settings.notificationTiming = .randomized
            try ledger.saveSample(at: sample, activity: "Observation", categoryID: nil, writer: "test", now: now)
            XCTAssertEqual(ledger.allocation(on: sample, now: now, calendar: utc).trackedMinutes, 60)
            let segment = try XCTUnwrap(ledger.inferredSegments(on: sample, now: now, calendar: utc).first)
            XCTAssertEqual(segment.start, sample.addingTimeInterval(-1800)); XCTAssertEqual(segment.end, sample.addingTimeInterval(1800))
        }
    }
}
