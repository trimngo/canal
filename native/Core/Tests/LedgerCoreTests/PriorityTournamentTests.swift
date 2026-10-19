import XCTest
@testable import LedgerCore

final class PriorityTournamentTests: XCTestCase {
    private func ids(_ count: Int) -> [String] { (0..<count).map { String(format: "%04d", $0) } }

    /// Use direct answers only here so the tree itself must retain branch wins.
    private func resolve(_ tree: inout PriorityTournament, limit: Int = 10,
                         answers: inout [InboxPreference]) throws -> Int {
        var questions = 0
        while true {
            let saved = answers
            tree.advance(limit: limit) { a, b in
                saved.first { ($0.winner == a && $0.loser == b) || ($0.winner == b && $0.loser == a) }?.winner
            }
            guard let pair = tree.matchup else { return questions }
            questions += 1
            guard questions < 2000 else { XCTFail("Tournament did not settle"); return questions }
            answers.append(InboxPreference(winner: min(pair[0], pair[1]), loser: max(pair[0], pair[1])))
            tree = try JSONDecoder().decode(PriorityTournament.self, from: JSONEncoder().encode(tree))
        }
    }

    func testHundredUnrelatedIdeasNeed99AnswersForFirstAndAtMost123ForTopFive() throws {
        var tree = PriorityTournament(ids: ids(100).reversed()), answers: [InboxPreference] = []
        XCTAssertEqual(try resolve(&tree, limit: 1, answers: &answers), 99)
        XCTAssertEqual(tree.confirmed, ["0000"])
        let extra = try resolve(&tree, limit: 5, answers: &answers)
        XCTAssertLessThanOrEqual(extra, 24)
        XCTAssertEqual(tree.confirmed, ids(5))
        XCTAssertEqual(tree.members, Set(ids(100))) // Extraction never completes/deletes tasks.
    }

    func testCompletingWinnerReusesBranchWinsAndNeedsAtMostSixQuestions() throws {
        var tree = PriorityTournament(ids: ids(100).reversed()), answers: [InboxPreference] = []
        _ = try resolve(&tree, limit: 1, answers: &answers)
        for completed in 0..<5 {
            tree.synchronize(ids: Array(ids(100).dropFirst(completed + 1)))
            XCTAssertLessThanOrEqual(try resolve(&tree, limit: 1, answers: &answers), 6)
            XCTAssertEqual(tree.confirmed, [String(format: "%04d", completed + 1)])
        }
    }

    func testDeletingOrRestoringLeafAndGrowingTreeNeverLosesOtherIdeas() throws {
        var tree = PriorityTournament(ids: ids(8)), answers: [InboxPreference] = []
        _ = try resolve(&tree, answers: &answers)
        tree.synchronize(ids: ids(8).filter { $0 != "0003" })
        _ = try resolve(&tree, answers: &answers)
        XCTAssertEqual(tree.confirmed, ids(8).filter { $0 != "0003" })
        tree.synchronize(ids: ids(17))
        XCTAssertTrue(tree.confirmed.isEmpty)
        _ = try resolve(&tree, answers: &answers)
        XCTAssertEqual(tree.confirmed, ids(10))
        XCTAssertEqual(tree.members, Set(ids(17)))
        XCTAssertEqual(tree.leaves.count, 32)
        XCTAssertEqual(tree.winners.count, 64)
    }

    func testInvalidatingChangedPrioritiesRemovesCachedWinners() throws {
        var tree = PriorityTournament(ids: ids(8)), answers: [InboxPreference] = []
        _ = try resolve(&tree, answers: &answers)
        tree.invalidateAnswers()
        XCTAssertTrue(tree.confirmed.isEmpty); XCTAssertNil(tree.matchup)
        tree.advance { _, _ in nil }
        XCTAssertNotNil(tree.matchup)
    }

    private func existingInbox(_ count: Int) -> Ledger {
        var ledger = Ledger(), ranking = InboxRanking()
        ledger.captures = ids(count).map { Capture(id: $0, text: "Idea \($0)", createdAt: Date(timeIntervalSince1970: Double($0)!), revision: Revision()) }
        ranking.ordered = Array(ids(count).prefix(10))
        ranking.topTen = TopTenRanking(backlog: Array(ids(count).dropFirst(10)), preferences: Array(ids(count).dropFirst(10)).map { InboxPreference(winner: "0009", loser: $0) })
        ledger.inboxRanking = ranking
        return ledger
    }

    private func finish(_ ledger: inout Ledger) throws -> Int {
        var questions = 0
        while let pair = ledger.rankingPair {
            questions += 1
            guard questions < 2000 else { XCTFail("Ranking did not settle"); return questions }
            ledger.chooseCapture(min(pair.first, pair.second), from: pair, writer: "phone")
            ledger = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        }
        return questions
    }

    func testExistingHundredIdeaInboxKeepsTopTenAndRequiresNoMandatorySetupQuestions() throws {
        var ledger = existingInbox(110)
        let original = ledger.captures
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs, ids(10))
        XCTAssertNil(ledger.rankingPair)
        ledger.prepareRanking(writer: "phone")
        XCTAssertNil(ledger.rankingPair) // Saved threshold answers prove all ten.
        XCTAssertEqual(ledger.inboxRanking?.priorityTournament?.confirmed, ids(10))
        XCTAssertEqual(ledger.captures, original)
        XCTAssertTrue(ledger.topTenIsVerified)
        XCTAssertEqual(ledger.backlogCaptures.count, 100)
    }

    func testAfterFirstBacklogReviewSubsequentVacancyUsesAtMostLogarithmicQuestions() throws {
        var ledger = existingInbox(110)
        ledger.prepareRanking(writer: "phone")
        ledger.setCaptureDone(id: "0000", done: true, writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs, Array(ids(10).dropFirst()))
        XCTAssertNil(ledger.rankingPair) // Refilling never interrupts capture.
        ledger.replenishTopTen(writer: "phone")
        XCTAssertLessThanOrEqual(try finish(&ledger), 99)
        XCTAssertEqual(ledger.rankedCaptureIDs, Array(ids(11).dropFirst()))
        ledger.setCaptureDone(id: "0001", done: true, writer: "phone")
        ledger.replenishTopTen(writer: "phone")
        XCTAssertLessThanOrEqual(try finish(&ledger), 6)
        XCTAssertEqual(ledger.rankedCaptureIDs, Array(ids(12).dropFirst(2)))
        XCTAssertTrue(ledger.topTenIsVerified)
    }

    func testPartlyBuiltTournamentSurvivesBackupAndPartialCloudAndCompanionMerges() throws {
        var phone = existingInbox(24)
        phone.prepareRanking(writer: "phone")
        phone.setCaptureDone(id: "0000", done: true, writer: "phone")
        phone.replenishTopTen(writer: "phone")
        let first = try XCTUnwrap(phone.rankingPair)
        phone.chooseCapture(min(first.first, first.second), from: first, writer: "phone")
        let saved = phone.inboxRanking?.priorityTournament
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        XCTAssertEqual(restored.inboxRanking?.priorityTournament, saved)
        var watch = Ledger(), cloud = Ledger()
        cloud.inboxRanking = restored.inboxRanking
        watch.merge(cloud); watch.merge(restored)
        watch.normalizeInboxRanking(writer: "watch")
        XCTAssertEqual(watch.rankingPair?.first, phone.rankingPair?.first)
        XCTAssertEqual(watch.rankingPair?.second, phone.rankingPair?.second)
        XCTAssertEqual(watch.inboxRanking?.priorityTournament, saved)
        try watch.addCapture(text: "New from Watch", id: "watch-new", writer: "watch")
        phone.merge(watch); phone.prepareRanking(writer: "phone")
        XCTAssertEqual(phone.rankingPair?.first, "watch-new")
        XCTAssertNotNil(phone.inboxRanking?.priorityTournament)
        _ = try finish(&phone)
        XCTAssertEqual(phone.captures.count, 25)
        XCTAssertTrue(phone.topTenIsVerified)
    }

    func testLegacyPausedSequentialTournamentMigratesWithoutRepeatingSavedAnswer() throws {
        var ledger = existingInbox(14)
        ledger.setCaptureDone(id: "0000", done: true, writer: "phone")
        ledger.inboxRanking?.topTen?.preferences.append(InboxPreference(winner: "0010", loser: "0011"))
        ledger.inboxRanking?.tournamentVersion = nil
        ledger.inboxRanking?.topTen?.tournament = BacklogTournament(champion: "0010", remaining: ["0012", "0013"])
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertNil(ledger.inboxRanking?.topTen?.tournament)
        let first = try XCTUnwrap(ledger.rankingPair)
        XCTAssertEqual(Set([first.first, first.second]), ["0010", "0012"])
        _ = try finish(&ledger)
        XCTAssertEqual(ledger.rankedCaptureIDs.last, "0010")
        XCTAssertTrue(ledger.topTenIsVerified)
    }

    func testSnapshotPartitionsInboxAndMatchesLegacyPublicViews() throws {
        var ledger = existingInbox(20)
        try ledger.addCapture(text: "New idea", id: "new", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        let snapshot = ledger.inboxSnapshot
        XCTAssertEqual(snapshot.ranked, ledger.rankedCaptures)
        XCTAssertEqual(snapshot.unseen, ledger.unseenCaptures)
        XCTAssertEqual(snapshot.inProgress, ledger.partiallyRankedCaptures)
        XCTAssertEqual(Set(snapshot.backlog.map(\.id)), Set(ledger.backlogCaptures.map(\.id)))
        XCTAssertEqual(snapshot.pair, ledger.rankingPair)
        XCTAssertEqual(snapshot.isVerified, ledger.topTenIsVerified)
        XCTAssertEqual(snapshot.ranked.count + snapshot.backlog.count + snapshot.unrankedCount, ledger.activeCaptures.count)
    }

    func testThousandIdeaSnapshotAndSavedTournamentBenchmark() throws {
        var ledger = existingInbox(1000)
        let start = Date()
        ledger.prepareRanking(writer: "phone")
        let tournamentTime = Date().timeIntervalSince(start)
        let snapshotStart = Date()
        let snapshot = ledger.inboxSnapshot
        let snapshotTime = Date().timeIntervalSince(snapshotStart)
        XCTAssertTrue(snapshot.isVerified)
        XCTAssertEqual(snapshot.backlog.count, 990)
        let state = try XCTUnwrap(ledger.inboxRanking?.priorityTournament)
        XCTAssertEqual(state.leaves.count, 1024)
        XCTAssertEqual(state.winners.count, 2048)
        print("RANKING BENCHMARK: 1000 ideas, saved-proof tournament \(tournamentTime)s, one screen snapshot \(snapshotTime)s, tree bytes \(try JSONEncoder().encode(state).count)")
    }
}
