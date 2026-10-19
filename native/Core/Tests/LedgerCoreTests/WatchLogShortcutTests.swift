import XCTest
@testable import LedgerCore

final class WatchLogShortcutTests: XCTestCase {
    func testOnlyTheComplicationLaunchRouteIsAccepted() {
        XCTAssertTrue(WatchLogShortcut.matches(WatchLogShortcut.url))
        XCTAssertTrue(WatchLogShortcut.matches(URL(string: "CANAL-DASH://log-now/")!))
        for value in ["https://log-now", "canal-dash://ideas", "canal-dash://log-now/another-action",
                      "canal-dash://log-now?text=Do+not+save", "canal-dash://log-now#data", "canal-dash://user@log-now"] {
            XCTAssertFalse(WatchLogShortcut.matches(URL(string: value)!), value)
        }
    }

    func testAcceptedComplicationSampleKeepsTimestampAndDoesNotDuplicateOnRetryOrMerge() throws {
        var watch = Ledger()
        let accepted = Date(timeIntervalSince1970: 1_792_060_000)
        let id = "watch-complication-test"
        try watch.saveQuickSample(id: id, at: accepted, activity: "Preparing classes", writer: "watch", now: accepted)
        let saved = watch
        try watch.saveQuickSample(id: id, at: accepted.addingTimeInterval(30), activity: "Duplicate callback", writer: "watch", now: accepted.addingTimeInterval(30))
        XCTAssertEqual(watch, saved)
        XCTAssertTrue(watch.confirmedCategoryIDs(for: watch.entries[0]).isEmpty)
        var phone = Ledger(); phone.merge(watch); phone.merge(saved)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertEqual(restored.entries[0].end, accepted)
        XCTAssertEqual(restored.entries[0].activity, "Preparing classes")
        XCTAssertTrue(restored.captures.isEmpty)
    }
}
