import XCTest
@testable import LedgerCore

final class InboxRankingTests: XCTestCase {
    private func fixture(_ ids: [String]) throws -> Ledger {
        var ledger = Ledger()
        for (i, id) in ids.enumerated() {
            try ledger.addCapture(text: id, id: id, writer: "phone", now: Date(timeIntervalSince1970: Double(i)))
        }
        return ledger
    }
    @discardableResult
    private func finish(_ ledger: inout Ledger) throws -> Int {
        ledger.prepareRanking(writer: "phone")
        var comparisons = 0
        while let pair = ledger.rankingPair {
            comparisons += 1
            guard comparisons < 100 else { XCTFail("Ranking did not finish"); return comparisons }
            ledger.chooseCapture(min(pair.first, pair.second), from: pair, writer: "phone")
            // Every answer crosses a durable save/relaunch boundary.
            let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
            XCTAssertEqual(restored.rankingPair, ledger.rankingPair)
            ledger = restored
        }
        return comparisons
    }
    func testInitialMergeSortUsesBinaryChoicesAndSurvivesEveryRelaunch() throws {
        var ledger = try fixture(["g", "a", "f", "b", "e", "c", "d"])
        let comparisons = try finish(&ledger)
        XCTAssertEqual(ledger.rankedCaptureIDs, ["a", "b", "c", "d", "e", "f", "g"])
        XCTAssertLessThanOrEqual(comparisons, 14)
        XCTAssertEqual(ledger.captures.count, 7)
    }
    func testNewIdeaUsesBinaryInsertionWithoutReorderingExistingIdeas() throws {
        var ledger = try fixture(["a", "c", "e", "g", "i", "k", "m", "o"])
        try finish(&ledger)
        let ordered = ledger.rankedCaptureIDs
        try ledger.addCapture(text: "h", id: "h", writer: "watch")
        XCTAssertEqual(ledger.rankedCaptureIDs, ordered)
        XCTAssertLessThanOrEqual(try finish(&ledger), 4)
        XCTAssertEqual(ledger.rankedCaptureIDs, ["a", "c", "e", "g", "h", "i", "k", "m", "o"])
    }
    func testCaptureArrivingMidSortIsRetainedAndRankedAfterTheCurrentSession() throws {
        var ledger = try fixture(["d", "b", "a", "c"])
        ledger.prepareRanking(writer: "phone")
        let pair = try XCTUnwrap(ledger.rankingPair)
        try ledger.addCapture(text: "e", id: "e", writer: "watch")
        XCTAssertEqual(ledger.rankingPair, pair)
        try finish(&ledger)
        XCTAssertEqual(ledger.rankedCaptureIDs, ["a", "b", "c", "d", "e"])
    }
    func testDeletionAndCompletionDuringSortingNeverPresentMissingIdeas() throws {
        var ledger = try fixture(["d", "b", "a", "c"])
        ledger.prepareRanking(writer: "phone")
        ledger.setCaptureDeleted("b", deleted: true, writer: "phone")
        ledger.setCaptureDone(id: "d", done: true, writer: "phone")
        try finish(&ledger)
        XCTAssertEqual(ledger.rankedCaptureIDs, ["a", "c"])
        XCTAssertEqual(ledger.captures.count, 4)
    }
    func testReRankingAndStaleComparisonCannotApplyToAnUnrelatedPair() throws {
        var ledger = try fixture(["d", "b", "a", "c"])
        ledger.prepareRanking(writer: "phone")
        let oldPair = try XCTUnwrap(ledger.rankingPair)
        ledger.chooseCapture(min(oldPair.first, oldPair.second), from: oldPair, writer: "phone")
        let before = ledger
        ledger.chooseCapture(oldPair.first, from: oldPair, writer: "phone")
        XCTAssertEqual(ledger, before)
        try finish(&ledger)
        ledger.rerankCapture("c", writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs, ["a", "b", "d"])
        try finish(&ledger)
        XCTAssertEqual(ledger.rankedCaptureIDs, ["a", "b", "c", "d"])
    }
    func testRankingProgressSyncsAndSingleOrEmptyInboxNeedsNoComparison() throws {
        var phone = try fixture(["b", "a"]), watch = phone
        phone.prepareRanking(writer: "phone"); watch.merge(phone)
        XCTAssertEqual(watch.rankingPair, phone.rankingPair)
        try finish(&phone); watch.merge(phone)
        XCTAssertEqual(watch.rankedCaptureIDs, ["a", "b"])
        var empty = Ledger(); empty.prepareRanking(writer: "phone"); XCTAssertNil(empty.rankingPair)
        var single = try fixture(["a"]); single.prepareRanking(writer: "phone")
        XCTAssertNil(single.rankingPair); XCTAssertEqual(single.rankedCaptureIDs, ["a"])
    }
    func testInitialComparisonsStartWithNewestCreatedIdeas() throws {
        var ledger = try fixture(["old", "middle", "new"])
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair, RankingPair(first: "new", second: "middle"))
        let pair = ledger.rankingPair
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(restored.rankingPair, pair)
    }
    func testPendingInsertionsChooseNewestWithoutDiscardingActiveComparison() throws {
        var ledger = try fixture(["a", "b"])
        try finish(&ledger)
        let baseline = Date(timeIntervalSince1970: 100)
        try ledger.addCapture(text: "Older pending", id: "older", writer: "phone", now: baseline)
        try ledger.addCapture(text: "Newer pending", id: "newer", writer: "phone", now: baseline.addingTimeInterval(1))
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "newer")
        let pair = try XCTUnwrap(ledger.rankingPair)
        try ledger.addCapture(text: "Arrived while comparing", id: "newest", writer: "phone", now: baseline.addingTimeInterval(2))
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair, pair)
        while ledger.inboxRanking?.insertion?.item == "newer", let current = ledger.rankingPair {
            ledger.chooseCapture(current.first, from: current, writer: "phone")
        }
        XCTAssertEqual(ledger.rankingPair?.first, "newest")
        XCTAssertEqual(ledger.rankedCaptureIDs.filter { $0 == "a" || $0 == "b" }, ["a", "b"])
    }
    func testImportedRemindersRankByOriginalCreationRatherThanImportOrder() throws {
        var ledger = Ledger()
        let baseline = Date(timeIntervalSince1970: 100)
        try ledger.addCapture(text: "Native idea", id: "native", writer: "phone", now: baseline.addingTimeInterval(10))
        ledger.importReminders([
            ReminderSnapshot(identifiers: ["old"], title: "Old reminder", createdAt: baseline),
            ReminderSnapshot(identifiers: ["new"], title: "New reminder", createdAt: baseline.addingTimeInterval(20))
        ], writer: "phone", now: baseline.addingTimeInterval(1000))
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair, RankingPair(first: "reminder-new", second: "native"))
        XCTAssertEqual(ledger.captures.first { $0.id == "reminder-old" }?.createdAt, baseline)
    }

}
