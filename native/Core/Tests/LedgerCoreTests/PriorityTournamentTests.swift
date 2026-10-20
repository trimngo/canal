import XCTest
@testable import LedgerCore

/// Compatibility with the retired engine; no tournament executes in Inbox.
final class PriorityTournamentTests: XCTestCase {
    private func legacy(_ count: Int = 110, limit: Int = 10) throws -> Ledger {
        var ledger = Ledger(), ranking = InboxRanking()
        let ids = (0..<count).map { String(format: "%04d", $0) }
        for id in ids { try ledger.addCapture(text: id, id: id, writer: "old-phone") }
        ranking.ordered = Array(ids.prefix(limit))
        ranking.topTen = TopTenRanking(backlog: Array(ids.dropFirst(limit)), preferences: ids.dropFirst(limit).map { InboxPreference(winner: String(format: "%04d", limit - 1), loser: $0) })
        ranking.priorityTournament = PriorityTournament(ids: ids)
        ranking.priorityTournament?.confirmed = ranking.ordered
        ranking.tournamentVersion = 1
        ledger.inboxRanking = ranking
        return ledger
    }

    func testCompletedTournamentMigratesExistingTopTenWithoutMandatoryQuestionsOrInventedDates() throws {
        var ledger = try legacy()
        let original = ledger.captures
        ledger = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs, (0..<10).map { String(format: "%04d", $0) })
        XCTAssertEqual(ledger.captures, original)
        XCTAssertNil(ledger.rankingPair)
        XCTAssertNil(ledger.inboxRanking?.priorityTournament)
        XCTAssertNotNil(ledger.inboxRanking?.screeningReview)
        XCTAssertEqual(ledger.inboxSnapshot.backlogWithoutReviewDateCount, 100)
        XCTAssertNil(ledger.inboxSnapshot.oldestBacklogReview)
    }

    func testPausedTournamentRetainsAnsweredEdgesAndMigratesCandidateToScreening() throws {
        var ledger = try legacy(12)
        try ledger.addCapture(text: "New", id: "0004a", writer: "old-phone")
        ledger.inboxRanking?.priorityTournament?.matchup = ["0004a", "0002"]
        ledger.inboxRanking?.topTen?.preferences.append(InboxPreference(winner: "0004a", loser: "0009"))
        ledger.inboxRanking?.topTen?.preferences.append(InboxPreference(winner: "0002", loser: "0004a"))
        let captures = ledger.captures, saved = ledger.inboxRanking?.topTen?.preferences
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertTrue((saved ?? []).allSatisfy { ledger.inboxRanking?.topTen?.preferences.contains($0) == true })
        XCTAssertNil(ledger.inboxRanking?.priorityTournament)
        XCTAssertNotNil(ledger.rankingPair)
        var count = 0
        while let pair = ledger.rankingPair {
            XCTAssertTrue(pair.first == "0004a" || pair.second == "0004a")
            XCTAssertNotEqual(pair.second, "0002") // Already answered; use the saved bound.
            count += 1
            ledger.chooseCapture(min(pair.first, pair.second), from: pair, writer: "phone")
        }
        XCTAssertLessThanOrEqual(count, 4)
        XCTAssertEqual(ledger.rankedCaptureIDs[5], "0004a")
        XCTAssertEqual(ledger.captures, captures)
    }

    func testRetiredSequentialTournamentPreservesIdeasAndSavedAnswerWhileOfferingFreshBacklogReview() throws {
        var ledger = try legacy(14)
        ledger.inboxRanking?.priorityTournament = nil
        ledger.inboxRanking?.tournamentVersion = nil
        ledger.inboxRanking?.topTen?.tournament = BacklogTournament(champion: "0010", remaining: ["0012", "0013"])
        ledger.inboxRanking?.topTen?.preferences.append(InboxPreference(winner: "0010", loser: "0011"))
        let saved = ledger.inboxRanking?.topTen?.preferences
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertNil(ledger.inboxRanking?.topTen?.tournament)
        XCTAssertTrue((saved ?? []).allSatisfy { ledger.inboxRanking?.topTen?.preferences.contains($0) == true })
        XCTAssertEqual(ledger.captures.count, 14)
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "0010")
        XCTAssertEqual(ledger.rankingPair?.second, "0005") // Ten legacy priorities leave vacancies in the expanded shortlist.
    }

    func testSnapshotPartitionsInboxAndMatchesPublicViews() throws {
        var ledger = try legacy(20)
        try ledger.addCapture(text: "New idea", id: "new", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        let snapshot = ledger.inboxSnapshot
        XCTAssertEqual(snapshot.ranked, ledger.rankedCaptures)
        XCTAssertEqual(snapshot.unseen, ledger.unseenCaptures)
        XCTAssertEqual(snapshot.inProgress, ledger.partiallyRankedCaptures)
        XCTAssertEqual(snapshot.backlog, ledger.backlogCaptures)
        XCTAssertEqual(snapshot.pair, ledger.rankingPair)
        XCTAssertEqual(snapshot.isVerified, ledger.topTenIsVerified)
        XCTAssertEqual(snapshot.ranked.count + snapshot.backlog.count + snapshot.unrankedCount, ledger.activeCaptures.count)
    }

    func testThousandIdeaInboxReviewsOneNewIdeaWithoutTraversingATournament() throws {
        var ledger = try legacy(1000, limit: 20)
        ledger.normalizeInboxRanking(writer: "phone")
        try ledger.addCapture(text: "New idea", id: "new", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        let pair = try XCTUnwrap(ledger.rankingPair)
        XCTAssertEqual(pair.first, "new"); XCTAssertEqual(pair.second, "0019")
        ledger.chooseCapture(pair.second, from: pair, writer: "phone")
        XCTAssertNil(ledger.rankingPair)
        XCTAssertNil(ledger.inboxRanking?.priorityTournament)
        XCTAssertEqual(ledger.inboxSnapshot.backlog.count, 981)
        XCTAssertTrue(ledger.inboxRanking?.screeningReview?.backlogRemaining.isEmpty == true)
    }
}
