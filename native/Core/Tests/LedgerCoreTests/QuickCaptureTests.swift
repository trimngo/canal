import XCTest
@testable import LedgerCore

final class QuickCaptureTests: XCTestCase {
    func testSiriTitleOnlyAndBodyOnlyNeedNoAdditionalInput() throws {
        XCTAssertEqual(try QuickCapture.text(title: "  Try shorter lessons  ", body: nil), "Try shorter lessons")
        XCTAssertEqual(try QuickCapture.text(title: nil, body: " Take a morning walk\n"), "Take a morning walk")
    }

    func testSiriKeepsBothTitleAndBodyWithoutRepeatingIdenticalText() throws {
        XCTAssertEqual(try QuickCapture.text(title: "Class idea", body: "Use more pictures"), "Class idea\nUse more pictures")
        XCTAssertEqual(try QuickCapture.text(title: "Walk", body: " walk "), "Walk")
    }

    func testEmptyAndOversizeSpeechCannotCreateAnEmptyOrTruncatedCapture() {
        XCTAssertThrowsError(try QuickCapture.text(title: " \n", body: nil))
        XCTAssertThrowsError(try QuickCapture.text(title: "Idea", body: String(repeating: "x", count: 500)))
    }

    func testSiriCaptureHasTimestampAndDoesNotChangeTimeSamples() throws {
        var ledger = Ledger()
        let timestamp = Date(timeIntervalSince1970: 1_792_060_000)
        let capture = try ledger.addCapture(text: QuickCapture.text(title: "Test a new lesson", body: nil), writer: "watch", now: timestamp)
        XCTAssertEqual(capture.createdAt, timestamp)
        XCTAssertEqual(capture.text, "Test a new lesson")
        XCTAssertEqual(ledger.captures, [capture])
        XCTAssertTrue(ledger.entries.isEmpty)
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(restored.captures.first?.createdAt, timestamp)
    }

    func testQuickReplyUsesResponseTimeAndStaysUnconfirmed() throws {
        var ledger = Ledger()
        let timestamp = Date(timeIntervalSince1970: 1_792_060_000)
        try ledger.saveQuickSample(id: "notification-one", at: timestamp, activity: "Working on app", writer: "watch", now: timestamp)
        let sample = try XCTUnwrap(ledger.entries.first)
        XCTAssertEqual(sample.end, timestamp)
        XCTAssertEqual(sample.activity, "Working on app")
        XCTAssertNil(ledger.confirmedCategoryID(for: sample))
        XCTAssertNil(sample.categoryID)
        XCTAssertEqual(ledger.suggestedCategory(for: sample.activity), "work")
    }

    func testRepeatedNotificationDeliveryDoesNotDuplicateOrMoveSample() throws {
        var ledger = Ledger()
        let timestamp = Date(timeIntervalSince1970: 1_792_060_000)
        try ledger.saveQuickSample(id: "notification-one", at: timestamp, activity: "Reading", writer: "watch", now: timestamp)
        let saved = ledger
        try ledger.saveQuickSample(id: "notification-one", at: timestamp.addingTimeInterval(20), activity: "Reading", writer: "phone", now: timestamp.addingTimeInterval(20))
        XCTAssertEqual(ledger, saved)
    }

    func testSeparateNotificationsCanRecordTheSameActivity() throws {
        var ledger = Ledger()
        let timestamp = Date(timeIntervalSince1970: 1_792_060_000)
        try ledger.saveQuickSample(id: "first", at: timestamp, activity: "Reading", writer: "watch", now: timestamp)
        try ledger.saveQuickSample(id: "second", at: timestamp, activity: "Reading", writer: "watch", now: timestamp)
        XCTAssertEqual(ledger.entries.count, 2)
    }

    func testCanceledOrInvalidReplyLeavesLedgerUntouched() {
        var ledger = Ledger()
        let previous = ledger
        XCTAssertThrowsError(try ledger.saveQuickSample(id: "empty", at: Date(), activity: " \n", writer: "watch"))
        XCTAssertEqual(ledger, previous)
    }

    func testReplayingASiriCaptureQueuePreservesIDTimestampAndCompletion() throws {
        var ledger = Ledger()
        let timestamp = Date(timeIntervalSince1970: 1_792_060_000)
        let capture = try ledger.addCapture(text: "A Watch thought", id: "queued-id", writer: "watch", now: timestamp)
        ledger.setCaptureDone(id: capture.id, done: true, writer: "phone")
        let saved = ledger
        try ledger.addCapture(text: capture.text, id: capture.id, writer: "watch", now: timestamp)
        XCTAssertEqual(ledger, saved)
        XCTAssertEqual(ledger.captures.first?.createdAt, timestamp)
    }
}
