import XCTest
@testable import LedgerCore

final class ScreeningInboxReviewTests: XCTestCase {
    private func ranked(backlog: Int = 0) throws -> Ledger {
        var ledger = Ledger(), ranking = InboxRanking()
        for n in 0..<(InboxRanking.priorityLimit + backlog) {
            let id = String(format: "%03d", n)
            try ledger.addCapture(text: id, id: id, writer: "old", now: Date(timeIntervalSince1970: Double(n)))
            if n < InboxRanking.priorityLimit { ranking.ordered.append(id) }
            else {
                if ranking.topTen == nil { ranking.topTen = TopTenRanking() }
                ranking.topTen?.backlog.append(id)
                ranking.topTen?.preferences.append(InboxPreference(winner: "019", loser: id))
            }
        }
        ledger.inboxRanking = ranking
        ledger.normalizeInboxRanking(writer: "phone")
        return ledger
    }
    @discardableResult
    private func answer(_ ledger: inout Ledger, prefer: (RankingPair) -> String = { min($0.first, $0.second) }) throws -> Int {
        var count = 0
        while let pair = ledger.rankingPair {
            count += 1
            guard count < 1000 else { XCTFail("Review did not finish"); return count }
            ledger.chooseCapture(prefer(pair), from: pair, writer: "phone")
            ledger = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        }
        return count
    }

    func testLowNewIdeaNeedsExactlyOneAnswerAndDoesNotStartBacklogReview() throws {
        var ledger = try ranked(backlog: 100)
        let original = ledger.rankedCaptureIDs
        try ledger.addCapture(text: "New", id: "new", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        let pair = try XCTUnwrap(ledger.rankingPair)
        XCTAssertEqual(pair.first, "new"); XCTAssertEqual(pair.second, "019")
        ledger.chooseCapture("019", from: pair, writer: "phone")
        XCTAssertNil(ledger.rankingPair)
        XCTAssertFalse(ledger.rankingIsActive)
        XCTAssertEqual(ledger.rankedCaptureIDs, original)
        XCTAssertEqual(ledger.backlogCaptures.count, 101)
        XCTAssertNil(ledger.inboxRanking?.priorityTournament)
    }

    func testEveryWinningPositionTakesAtMostSixAnswersAndDisplacesOnlyTwentieth() throws {
        for position in 0..<InboxRanking.priorityLimit {
            var ledger = try ranked(backlog: 100)
            let original = ledger.rankedCaptureIDs
            try ledger.addCapture(text: "New", id: "new", writer: "phone")
            ledger.prepareRanking(writer: "phone")
            func score(_ id: String) -> Int { id == "new" ? position * 2 - 1 : Int(id)! * 2 }
            let count = try answer(&ledger) { score($0.first) < score($0.second) ? $0.first : $0.second }
            XCTAssertLessThanOrEqual(count, 6)
            var expected = original; expected.insert("new", at: position); expected.removeLast()
            XCTAssertEqual(ledger.rankedCaptureIDs, expected)
            XCTAssertTrue(ledger.backlogCaptures.contains { $0.id == "019" })
            XCTAssertEqual(ledger.backlogCaptures.count, 101)
        }
    }

    func testEmptyShortlistBuildsIncrementallyInsteadOfWaitingForTournamentWinner() throws {
        var ledger = Ledger()
        for index in 0..<100 {
            try ledger.addCapture(text: "Idea", id: String(format: "%03d", index), writer: "phone", now: Date(timeIntervalSince1970: Double(index)))
        }
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs, ["099"])
        let first = try XCTUnwrap(ledger.rankingPair)
        XCTAssertEqual(Set([first.first, first.second]), ["099", "098"])
        ledger.chooseCapture("098", from: first, writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs, ["098", "099"])
        XCTAssertEqual(ledger.captures.count, 100)
    }

    func testNewIdeasFinishBeforeOptionalBacklogPassAndOldRejectionIsAskedFresh() throws {
        var ledger = try ranked(backlog: 2)
        try ledger.addCapture(text: "New", id: "new", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(try answer(&ledger), 1)
        XCTAssertNil(ledger.rankingPair)
        ledger.prepareRanking(writer: "phone")
        XCTAssertTrue(ledger.inboxSnapshot.reviewingBacklog)
        XCTAssertEqual(ledger.rankingPair?.first, "020")
        XCTAssertEqual(ledger.rankingPair?.second, "019") // Saved rejection must not auto-dismiss it.
        XCTAssertEqual(try answer(&ledger), 3) // Each backlog idea exactly once, including "new".
        XCTAssertNil(ledger.rankingPair)
    }

    func testBacklogUsesOldestRecordedReviewWithUndatedItemsFirst() throws {
        var ledger = try ranked(backlog: 3)
        ledger.inboxRanking?.screeningReview?.lastReviewed = ["020": Date(timeIntervalSince1970: 200), "021": Date(timeIntervalSince1970: 100)]
        XCTAssertEqual(ledger.backlogCaptures.map(\.id), ["022", "021", "020"])
        XCTAssertEqual(ledger.inboxSnapshot.oldestBacklogReview, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(ledger.inboxSnapshot.backlogWithoutReviewDateCount, 1)
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "022")
        let first = try XCTUnwrap(ledger.rankingPair)
        ledger.chooseCapture(first.second, from: first, writer: "phone", now: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(ledger.rankingPair?.first, "021")
        XCTAssertEqual(ledger.inboxSnapshot.backlogWithoutReviewDateCount, 0)
        XCTAssertEqual(ledger.captures.first { $0.id == "022" }?.createdAt, Date(timeIntervalSince1970: 22))
    }

    func testShowingOrPausingQuestionDoesNotClaimItWasReviewed() throws {
        var ledger = try ranked(backlog: 1)
        ledger.prepareRanking(writer: "phone")
        ledger.markRankingPresented(writer: "phone")
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertNil(ledger.inboxRanking?.screeningReview?.lastReviewed["020"])
        XCTAssertEqual(ledger.inboxSnapshot.backlogWithoutReviewDateCount, 1)
        let pair = try XCTUnwrap(ledger.rankingPair), now = Date(timeIntervalSince1970: 12345)
        ledger.chooseCapture(pair.second, from: pair, writer: "phone", now: now)
        XCTAssertEqual(ledger.inboxRanking?.screeningReview?.lastReviewed[pair.first], now)
        XCTAssertEqual(ledger.inboxRanking?.screeningReview?.lastReviewed[pair.second], now)
        XCTAssertEqual(ledger.inboxSnapshot.oldestBacklogReview, now)
    }

    func testNewArrivalDoesNotInterruptVisibleBacklogQuestionButExplicitReviewPrioritizesIt() throws {
        var ledger = try ranked(backlog: 3)
        ledger.prepareRanking(writer: "phone")
        let pair = try XCTUnwrap(ledger.rankingPair), saved = ledger.inboxRanking
        try ledger.addCapture(text: "Newest", id: "new", writer: "watch")
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair, pair); XCTAssertEqual(ledger.inboxRanking, saved)
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "new")
        XCTAssertEqual(try answer(&ledger), 1)
        XCTAssertNil(ledger.rankingPair) // Can stop immediately after reviewing the new arrival.
    }

    func testAnsweringBacklogQuestionSwitchesToNewArrivalWithoutDiscardingPartialAnswers() throws {
        var ledger = try ranked(backlog: 3)
        ledger.prepareRanking(writer: "phone")
        let visible = try XCTUnwrap(ledger.rankingPair)
        try ledger.addCapture(text: "Newest", id: "new", writer: "watch")
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair, visible)
        ledger.chooseCapture(visible.first, from: visible, writer: "phone") // Backlog candidate wins its screening.
        XCTAssertEqual(ledger.rankingPair?.first, "new")
        XCTAssertTrue(ledger.inboxRanking?.topTen?.preferences.contains(InboxPreference(winner: visible.first, loser: visible.second)) == true)
        let question = try XCTUnwrap(ledger.rankingPair)
        ledger.chooseCapture(question.second, from: question, writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, visible.first)
        XCTAssertNotEqual(ledger.rankingPair?.second, visible.second) // Don't repeat the answered screen.
    }

    func testCompletionLeavesOptionalVacancyAndNewestIsScreenedBeforeBacklog() throws {
        var ledger = try ranked(backlog: 3)
        ledger.setCaptureDone(id: "000", done: true, writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs.count, 19); XCTAssertNil(ledger.rankingPair)
        try ledger.addCapture(text: "Newest", id: "new", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "new")
        try answer(&ledger)
        XCTAssertEqual(ledger.rankedCaptureIDs.last, "new")
        XCTAssertFalse(ledger.topTenIsVerified) // Backlog could contain a better replacement.
        ledger.prepareRanking(writer: "phone")
        try answer(&ledger)
        XCTAssertEqual(ledger.rankedCaptureIDs.last, "020")
    }

    func testRerankingClearsOnlySelectedIdeaEvidenceAndDoesNotReorderOtherPriorities() throws {
        var ledger = try ranked(backlog: 3)
        let others = ledger.rankedCaptureIDs.filter { $0 != "005" }
        ledger.rerankCapture("005", writer: "phone")
        try answer(&ledger) { pair in
            XCTAssertTrue(pair.first == "005" || pair.second == "005")
            return pair.first == "005" ? pair.second : pair.first
        }
        XCTAssertEqual(ledger.rankedCaptureIDs, others + ["005"])
        ledger.rerankCapture("022", writer: "phone")
        try answer(&ledger) { pair in
            XCTAssertTrue(pair.first == "022" || pair.second == "022")
            return "022"
        }
        XCTAssertEqual(ledger.rankedCaptureIDs.first, "022")
    }

    func testExplicitRerankStartsWithChosenIdeaEvenWhenNewerIdeasAreWaiting() throws {
        var ledger = try ranked(backlog: 3)
        try ledger.addCapture(text: "Newest", id: "new", writer: "phone")
        ledger.rerankCapture("022", writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "022")
        XCTAssertTrue(ledger.unseenCaptures.contains { $0.id == "new" })
    }

    func testPausedInsertionReviewDatesAndBacklogPassSurviveBackupCloudAndCompanion() throws {
        var phone = try ranked(backlog: 3)
        phone.prepareRanking(writer: "phone")
        let first = try XCTUnwrap(phone.rankingPair)
        phone.chooseCapture(first.first, from: first, writer: "phone") // Wins screen, insertion still pending.
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        var cloud = Ledger(); cloud.inboxRanking = restored.inboxRanking
        var watch = Ledger(); watch.merge(cloud); watch.merge(restored)
        watch.normalizeInboxRanking(writer: "watch")
        XCTAssertEqual(watch.inboxRanking, phone.inboxRanking)
        XCTAssertEqual(watch.rankingPair, phone.rankingPair)
        XCTAssertEqual(watch.inboxSnapshot.oldestBacklogReview, phone.inboxSnapshot.oldestBacklogReview)
        var delivery = CompanionQuickDelivery()
        let data = try XCTUnwrap(delivery.prepare(phone, id: "review"))
        let packet = try JSONDecoder().decode(CompanionQuickPacket.self, from: data)
        var companion = Ledger(); companion.merge(packet.ledger); companion.merge(phone)
        XCTAssertEqual(companion.inboxRanking, phone.inboxRanking)
        try answer(&watch)
        phone.merge(watch)
        XCTAssertEqual(phone.rankedCaptureIDs, watch.rankedCaptureIDs)
        XCTAssertEqual(phone.inboxRanking?.screeningReview, watch.inboxRanking?.screeningReview)
    }
}
