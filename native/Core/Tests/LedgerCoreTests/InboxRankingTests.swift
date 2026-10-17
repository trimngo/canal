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
        var comparisons = 0
        repeat {
            if ledger.rankingPair == nil {
                if !ledger.unrankedCaptures.isEmpty { ledger.prepareRanking(writer: "phone") }
                else if ledger.needsTopTenReplenishment { ledger.replenishTopTen(writer: "phone") }
            }
            while let pair = ledger.rankingPair {
                comparisons += 1
                guard comparisons < 2000 else { XCTFail("Ranking did not finish"); return comparisons }
                ledger.chooseCapture(min(pair.first, pair.second), from: pair, writer: "phone")
                let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
                XCTAssertEqual(restored.rankingPair, ledger.rankingPair)
                ledger = restored
            }
        } while !ledger.unrankedCaptures.isEmpty || ledger.needsTopTenReplenishment
        return comparisons
    }
    func testInitialBinaryInsertionUsesChoicesAndSurvivesEveryRelaunch() throws {
        var ledger = try fixture(["g", "a", "f", "b", "e", "c", "d"])
        let comparisons = try finish(&ledger)
        XCTAssertEqual(ledger.rankedCaptureIDs, ["a", "b", "c", "d", "e", "f", "g"])
        XCTAssertLessThanOrEqual(comparisons, 21)
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
        XCTAssertEqual(ledger.rankedCaptureIDs, ["new"])
        XCTAssertEqual(ledger.rankingPair?.first, "middle"); XCTAssertEqual(ledger.rankingPair?.second, "new")
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
        while ledger.inboxRanking?.topTen?.candidate?.item == "newer", let current = ledger.rankingPair {
            ledger.chooseCapture(current.first, from: current, writer: "phone")
        }
        XCTAssertEqual(ledger.rankingPair?.first, "older")
        try finish(&ledger)
        XCTAssertTrue(ledger.rankedCaptureIDs.contains("newest"))
        XCTAssertEqual(ledger.rankedCaptureIDs.filter { $0 == "a" || $0 == "b" }, ["a", "b"])
    }
    func testRankedAndWaitingListsPartitionActiveIdeasAndKeepUserOrder() throws {
        var ledger = try fixture(["a", "b", "c"])
        try finish(&ledger)
        ledger.setCaptureDone(id: "b", done: true, writer: "phone")
        ledger.setCaptureDeleted("c", deleted: true, writer: "phone")
        try ledger.addCapture(text: "Manual idea", id: "manual", writer: "phone", now: Date(timeIntervalSince1970: 100))
        ledger.importReminders([
            ReminderSnapshot(identifiers: ["new"], title: "New reminder", createdAt: Date(timeIntervalSince1970: 120)),
            ReminderSnapshot(identifiers: ["old"], title: "Older reminder", createdAt: Date(timeIntervalSince1970: 20))
        ], writer: "phone")
        XCTAssertEqual(ledger.rankedCaptures.map(\.id), ["a"])
        XCTAssertEqual(ledger.unrankedCaptures.map(\.id), ["reminder-new", "manual", "reminder-old"])
        XCTAssertEqual(Set((ledger.rankedCaptures + ledger.unrankedCaptures).map(\.id)), Set(ledger.activeCaptures.map(\.id)))
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "reminder-new")
        XCTAssertEqual(ledger.unrankedCaptures.count, 3)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(restored.unrankedCaptures, ledger.unrankedCaptures)
        try finish(&ledger)
        XCTAssertTrue(ledger.unrankedCaptures.isEmpty)
        XCTAssertEqual(ledger.rankedCaptures.count, 4)
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
        XCTAssertEqual(ledger.rankedCaptureIDs, ["reminder-new"])
        XCTAssertEqual(ledger.rankingPair?.first, "native"); XCTAssertEqual(ledger.rankingPair?.second, "reminder-new")
        XCTAssertEqual(ledger.captures.first { $0.id == "reminder-old" }?.createdAt, baseline)
    }

    private func legacyRanked(_ count: Int = 10) throws -> Ledger {
        let ids = (0..<count).map { String(format: "%03d", $0) }
        var ledger = try fixture(ids), ranking = InboxRanking()
        ranking.ordered = ids; ranking.revision = ledger.nextRevision(writer: "old-phone")
        ledger.inboxRanking = ranking
        return ledger
    }
    @discardableResult
    private func answerBatch(_ ledger: inout Ledger, prefer: (RankingPair) -> String) throws -> Int {
        var count = 0
        while let pair = ledger.rankingPair {
            count += 1
            guard count < 2000 else { XCTFail("Session did not finish"); return count }
            ledger.chooseCapture(prefer(pair), from: pair, writer: "phone")
            ledger = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        }
        return count
    }

    func testBelowThresholdRequiresExactlyOneComparisonAndStaysDistinguishableFromNew() throws {
        var ledger = try legacyRanked()
        ledger.normalizeInboxRanking(writer: "phone")
        let top = ledger.rankedCaptureIDs
        try ledger.addCapture(text: "Low priority", id: "020", writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs, top)
        XCTAssertFalse(ledger.topTenIsVerified)
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "020"); XCTAssertEqual(ledger.rankingPair?.second, "009")
        XCTAssertEqual(try answerBatch(&ledger) { min($0.first, $0.second) }, 1)
        XCTAssertEqual(ledger.rankedCaptureIDs, top)
        XCTAssertEqual(ledger.backlogCaptures.map(\.id), ["020"])
        XCTAssertTrue(ledger.unrankedCaptures.isEmpty)
        XCTAssertTrue(ledger.topTenIsVerified)
    }

    func testAllTenQualifyingInsertionPositionsUseAtMostFiveComparisons() throws {
        for position in 0..<10 {
            var ledger = try legacyRanked()
            let before = ledger.rankedCaptureIDs
            try ledger.addCapture(text: "Candidate", id: "candidate", writer: "phone")
            ledger.prepareRanking(writer: "phone")
            func score(_ id: String) -> Int { id == "candidate" ? position * 2 - 1 : Int(id)! * 2 }
            let count = try answerBatch(&ledger) { score($0.first) < score($0.second) ? $0.first : $0.second }
            XCTAssertLessThanOrEqual(count, 5)
            var expected = before; expected.insert("candidate", at: position); expected.removeLast()
            XCTAssertEqual(ledger.rankedCaptureIDs, expected)
            XCTAssertEqual(ledger.backlogCaptures.map(\.id), ["009"])
            XCTAssertEqual(ledger.rankedCaptureIDs.filter { $0 != "candidate" }, Array(before.dropLast()))
            XCTAssertTrue(ledger.topTenIsVerified)
        }
    }

    func testSessionReviewsAllWaitingIdeasAndCaptureDoesNotStartOrInterruptRanking() throws {
        var ledger = try fixture((0..<18).map { String(format: "%03d", $0) })
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertNil(ledger.rankingPair); XCTAssertTrue(ledger.rankedCaptureIDs.isEmpty)
        ledger.prepareRanking(writer: "phone")
        let pair = try XCTUnwrap(ledger.rankingPair)
        let originalState = ledger.inboxRanking
        try ledger.addCapture(text: "Just captured", id: "newest", writer: "watch", now: Date())
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair, pair); XCTAssertEqual(ledger.inboxRanking, originalState)
        try answerBatch(&ledger) { min($0.first, $0.second) }
        XCTAssertEqual(ledger.rankedCaptureIDs, (0..<10).map { String(format: "%03d", $0) })
        XCTAssertEqual(ledger.backlogCaptures.count, 8)
        XCTAssertEqual(ledger.unrankedCaptures.map(\.id), ["newest"])
        XCTAssertFalse(ledger.rankingIsActive)
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "newest")
    }

    func testUnseenCandidatesGetFirstLookBeforePartialInsertionsResume() throws {
        var ledger = try legacyRanked()
        let date = Date(timeIntervalSince1970: 100)
        for (index, id) in ["a", "b", "c"].enumerated() {
            try ledger.addCapture(text: id, id: id, writer: "phone", now: date.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(ledger.unseenCaptures.map(\.id), ["c", "b", "a"])
        XCTAssertTrue(ledger.partiallyRankedCaptures.isEmpty)
        ledger.prepareRanking(writer: "phone")
        for (id, remaining) in [("c", 2), ("b", 1), ("a", 0)] {
            let pair = try XCTUnwrap(ledger.rankingPair)
            XCTAssertEqual(pair.first, id)
            XCTAssertEqual(pair.second, "009") // Every candidate first meets the threshold.
            XCTAssertEqual(ledger.unseenCaptures.count, remaining)
            XCTAssertTrue(ledger.partiallyRankedCaptures.contains { $0.id == id })
            ledger.chooseCapture(id, from: pair, writer: "phone")
            ledger = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        }
        XCTAssertTrue(ledger.unseenCaptures.isEmpty)
        XCTAssertEqual(Set(ledger.partiallyRankedCaptures.map(\.id)), ["a", "b", "c"])
        XCTAssertEqual(ledger.rankingPair?.first, "a") // Last first-look candidate can now finish.
        let scores: [String: Double] = ["a": 1.5, "b": 3.5, "c": 5.5]
        try answerBatch(&ledger) {
            (scores[$0.first] ?? Double($0.first)!) < (scores[$0.second] ?? Double($0.second)!) ? $0.first : $0.second
        }
        XCTAssertEqual(ledger.rankedCaptureIDs, ["000", "001", "a", "002", "003", "b", "004", "005", "c", "006"])
        XCTAssertTrue(ledger.partiallyRankedCaptures.isEmpty)
        XCTAssertTrue(ledger.topTenIsVerified)
    }

    func testSeeingWithoutAnswerMovesToProgressAndSurvivesBackupSyncAndRerank() throws {
        var ledger = try legacyRanked()
        try ledger.addCapture(text: "Seen", id: "seen", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        let pair = try XCTUnwrap(ledger.rankingPair)
        XCTAssertEqual(ledger.partiallyRankedCaptures.map(\.id), ["seen"])
        XCTAssertTrue(ledger.unseenCaptures.isEmpty)
        var restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        var watch = Ledger(); watch.merge(restored)
        XCTAssertEqual(watch.partiallyRankedCaptures.map(\.id), ["seen"])
        restored.prepareRanking(writer: "phone")
        XCTAssertEqual(restored.rankingPair, pair)
        restored.rerankCapture("000", writer: "phone")
        XCTAssertTrue(restored.partiallyRankedCaptures.contains { $0.id == "seen" })
        XCTAssertFalse(restored.unseenCaptures.contains { $0.id == "seen" })
        restored.setCaptureDeleted("seen", deleted: true, writer: "phone")
        XCTAssertFalse(restored.partiallyRankedCaptures.contains { $0.id == "seen" })
        restored.setCaptureDeleted("seen", deleted: false, writer: "phone")
        XCTAssertTrue(restored.partiallyRankedCaptures.contains { $0.id == "seen" })
        try finish(&restored)
    }

    func testPreviousTopTenStateWithoutPresentationFieldsRemainsRecoverable() throws {
        var ledger = try legacyRanked()
        try ledger.addCapture(text: "Partial", id: "partial", writer: "phone")
        try ledger.addCapture(text: "Not shown", id: "unseen", writer: "phone", now: Date(timeIntervalSince1970: 1))
        ledger.prepareRanking(writer: "phone")
        ledger.inboxRanking?.topTen?.presented = nil
        ledger.inboxRanking?.topTen?.deferred = nil
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(restored.partiallyRankedCaptures.map(\.id), ["partial"])
        XCTAssertEqual(restored.unseenCaptures.map(\.id), ["unseen"])
        XCTAssertEqual(restored.rankingPair, ledger.rankingPair)
    }

    func testUnsortedBacklogReplenishmentFindsTrueBestAndCanPauseAtEveryAnswer() throws {
        var ledger = try legacyRanked()
        for id in ["011", "015", "020"] { try ledger.addCapture(text: id, id: id, writer: "phone") }
        try finish(&ledger)
        ledger.setCaptureDone(id: "000", done: true, writer: "watch")
        XCTAssertEqual(ledger.rankedCaptureIDs.count, 9)
        XCTAssertTrue(ledger.needsTopTenReplenishment); XCTAssertNil(ledger.rankingPair)
        XCTAssertFalse(ledger.topTenIsVerified)
        ledger.replenishTopTen(writer: "phone")
        XCTAssertEqual(try answerBatch(&ledger) { min($0.first, $0.second) }, 2)
        XCTAssertEqual(ledger.rankedCaptureIDs.last, "011")
        XCTAssertEqual(Set(ledger.backlogCaptures.map(\.id)), ["015", "020"])
        XCTAssertTrue(ledger.topTenIsVerified)
        ledger.setCaptureDeleted("011", deleted: true, writer: "phone")
        ledger.replenishTopTen(writer: "phone")
        XCTAssertEqual(try answerBatch(&ledger) { min($0.first, $0.second) }, 0) // Previous tournament already established 015 > 020.
        XCTAssertEqual(ledger.rankedCaptureIDs.last, "015")
    }

    func testLegacyFullOrderMigratesTopTenAndReusesTailForVacancyWithoutComparisons() throws {
        var ledger = try legacyRanked(15)
        let oldCaptures = ledger.captures
        let legacyBytes = try JSONEncoder().encode(ledger)
        ledger = try JSONDecoder().decode(Ledger.self, from: legacyBytes)
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs, (0..<10).map { String(format: "%03d", $0) })
        XCTAssertEqual(Set(ledger.backlogCaptures.map(\.id)), Set((10..<15).map { String(format: "%03d", $0) }))
        XCTAssertEqual(ledger.captures, oldCaptures)
        ledger.setCaptureDeleted("000", deleted: true, writer: "phone")
        XCTAssertTrue(ledger.needsTopTenReplenishment)
        XCTAssertEqual(ledger.rankedCaptureIDs.count, 9) // Refilling is optional.
        ledger.replenishTopTen(writer: "phone")
        XCTAssertNil(ledger.rankingPair)
        XCTAssertEqual(ledger.rankedCaptureIDs.last, "010")
        XCTAssertEqual(ledger.rankedCaptureIDs.count, 10)
        XCTAssertTrue(ledger.topTenIsVerified)
    }

    func testRerankedTopIdeaCanFallBelowBacklogWithoutFalselyVerifyingTopTen() throws {
        var ledger = try legacyRanked(12)
        ledger.normalizeInboxRanking(writer: "phone")
        let remaining = ledger.rankedCaptureIDs.filter { $0 != "005" }
        ledger.rerankCapture("005", writer: "phone")
        XCTAssertEqual(ledger.rankedCaptureIDs, remaining)
        try answerBatch(&ledger) { $0.first == "005" ? $0.second : min($0.first, $0.second) }
        XCTAssertEqual(ledger.rankedCaptureIDs.last, "005")
        XCTAssertTrue(ledger.needsTopTenReplenishment)
        XCTAssertFalse(ledger.topTenIsVerified)
        ledger.replenishTopTen(writer: "phone")
        try answerBatch(&ledger) { $0.first == "005" ? $0.second : $0.second == "005" ? $0.first : min($0.first, $0.second) }
        XCTAssertEqual(ledger.rankedCaptureIDs, remaining + ["010"])
        XCTAssertTrue(ledger.backlogCaptures.contains { $0.id == "005" })
        XCTAssertTrue(ledger.topTenIsVerified)
    }

    func testBacklogIdeaCanBeRerankedToFirstAndInterruptedCandidateIsNotLost() throws {
        var ledger = try legacyRanked(12)
        try ledger.addCapture(text: "Pending", id: "pending", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "pending")
        ledger.rerankCapture("011", writer: "phone")
        XCTAssertTrue(ledger.unrankedCaptures.contains { $0.id == "pending" })
        XCTAssertLessThanOrEqual(try answerBatch(&ledger) { _ in "011" }, 5)
        XCTAssertEqual(ledger.rankedCaptureIDs.first, "011")
        XCTAssertTrue(ledger.backlogCaptures.contains { $0.id == "009" })
        XCTAssertFalse(ledger.topTenIsVerified) // The interrupted new idea still needs review.
        try finish(&ledger)
        XCTAssertEqual(ledger.captures.count, 13)
    }

    func testLegacyPartialInsertionRetainsAnsweredBounds() throws {
        var ledger = try legacyRanked(15)
        try ledger.addCapture(text: "Partially ranked", id: "003a", writer: "old-phone")
        let base = ledger.inboxRanking!.ordered
        ledger.inboxRanking?.insertion = InsertionRanking(item: "003a", base: base, low: 2, high: 5)
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertLessThanOrEqual(try answerBatch(&ledger) { min($0.first, $0.second) }, 2)
        XCTAssertEqual(ledger.rankedCaptureIDs, ["000", "001", "002", "003", "003a", "004", "005", "006", "007", "008"])
        XCTAssertEqual(ledger.captures.count, 16)
    }

    func testLegacyPartialMergeKeepsKnownRunAndHeadComparisons() throws {
        var ledger = try fixture(["a", "b", "c", "d"])
        var ranking = InboxRanking()
        ranking.merge = MergeRanking(runs: [], nextRuns: [], left: ["b"], right: ["c", "d"], merged: ["a"])
        ledger.inboxRanking = ranking
        ledger.normalizeInboxRanking(writer: "phone")
        let preferences = ledger.inboxRanking?.topTen?.preferences ?? []
        XCTAssertTrue(preferences.contains(InboxPreference(winner: "a", loser: "b")))
        XCTAssertTrue(preferences.contains(InboxPreference(winner: "a", loser: "c")))
        XCTAssertTrue(preferences.contains(InboxPreference(winner: "c", loser: "d")))
        try finish(&ledger)
        XCTAssertEqual(ledger.rankedCaptureIDs, ["a", "b", "c", "d"])
        XCTAssertEqual(ledger.captures.count, 4)
    }

    func testCompletionDeletionAndRestorationDuringTournamentKeepAllCandidatesRecoverable() throws {
        var ledger = try legacyRanked()
        for id in ["011", "012", "013"] { try ledger.addCapture(text: id, id: id, writer: "phone") }
        try finish(&ledger)
        ledger.setCaptureDone(id: "000", done: true, writer: "phone")
        ledger.replenishTopTen(writer: "phone")
        let oldPair = try XCTUnwrap(ledger.rankingPair)
        ledger.setCaptureDeleted(oldPair.first, deleted: true, writer: "phone")
        let before = ledger
        ledger.chooseCapture(oldPair.second, from: oldPair, writer: "phone")
        XCTAssertEqual(ledger, before)
        try answerBatch(&ledger) { min($0.first, $0.second) }
        XCTAssertEqual(ledger.rankedCaptureIDs.count, 10)
        ledger.setCaptureDeleted(oldPair.first, deleted: false, writer: "phone")
        XCTAssertTrue(ledger.backlogCaptures.contains { $0.id == oldPair.first })
        XCTAssertFalse(ledger.topTenIsVerified)
        ledger.replenishTopTen(writer: "phone")
        try answerBatch(&ledger) { min($0.first, $0.second) }
        XCTAssertTrue(ledger.topTenIsVerified)
    }

    func testCloudStylePartialMergeCompanionAndBackupPreserveSessionAndConcurrentCaptures() throws {
        var phone = try legacyRanked(), watch = phone
        try phone.addCapture(text: "Candidate", id: "004a", writer: "phone")
        phone.prepareRanking(writer: "phone")
        let first = try XCTUnwrap(phone.rankingPair)
        phone.chooseCapture(first.first, from: first, writer: "phone")
        var cloudRecord = Ledger(); cloudRecord.categories = []; cloudRecord.inboxRanking = phone.inboxRanking
        watch.merge(cloudRecord)
        watch.merge(phone)
        XCTAssertEqual(watch.rankingPair, phone.rankingPair)
        try watch.addCapture(text: "Watch capture", id: "watch-new", writer: "watch")
        phone.merge(watch); phone.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(phone.rankingPair, watch.rankingPair)
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        XCTAssertEqual(restored.inboxRanking, phone.inboxRanking)
        XCTAssertTrue(restored.unrankedCaptures.contains { $0.id == "watch-new" })
        try answerBatch(&phone) { min($0.first, $0.second) }
        watch.merge(phone)
        XCTAssertEqual(watch.rankedCaptureIDs, phone.rankedCaptureIDs)
        XCTAssertEqual(watch.backlogCaptures, phone.backlogCaptures)
        XCTAssertTrue(watch.unrankedCaptures.contains { $0.id == "watch-new" })
    }

    func testTopTenMatchesFullOrderingAcrossArrivalOrdersVacanciesAndRestores() throws {
        var seed: UInt64 = 71
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1
            return Int((seed >> 32) % UInt64(bound))
        }
        for _ in 0..<15 {
            var ids = (0..<24).map { String(format: "%03d", $0) }
            for index in (1..<ids.count).reversed() { ids.swapAt(index, next(index + 1)) }
            var ledger = try fixture(ids)
            try finish(&ledger)
            XCTAssertEqual(ledger.rankedCaptureIDs, Array(ids.sorted().prefix(10)))
            XCTAssertTrue(ledger.topTenIsVerified)
            for _ in 0..<4 {
                let removed = ledger.rankedCaptureIDs[next(ledger.rankedCaptureIDs.count)]
                ledger.setCaptureDeleted(removed, deleted: true, writer: "phone")
                XCTAssertFalse(ledger.topTenIsVerified)
                XCTAssertNil(ledger.rankingPair) // No forced replenishment.
                ledger.replenishTopTen(writer: "phone")
                try answerBatch(&ledger) { min($0.first, $0.second) }
                XCTAssertEqual(ledger.rankedCaptureIDs, Array(ledger.activeCaptures.map(\.id).sorted().prefix(10)))
                XCTAssertTrue(ledger.topTenIsVerified)
                ledger.setCaptureDeleted(removed, deleted: false, writer: "phone")
                ledger.replenishTopTen(writer: "phone")
                try answerBatch(&ledger) { min($0.first, $0.second) }
                XCTAssertEqual(ledger.rankedCaptureIDs, Array(ids.sorted().prefix(10)))
                XCTAssertTrue(ledger.topTenIsVerified)
            }
        }
    }

    func testReplenishmentSkipsUnknownLoserPairsWhenKnownBestWasDisplacedLast() throws {
        var ledger = try legacyRanked(14)
        for id in ["015", "016"] { try ledger.addCapture(text: id, id: id, writer: "phone") }
        try finish(&ledger)
        try ledger.addCapture(text: "Urgent", id: "urgent", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        try answerBatch(&ledger) { _ in "urgent" }
        XCTAssertEqual(ledger.inboxRanking?.topTen?.backlog.last, "009")
        ledger.setCaptureDone(id: "000", done: true, writer: "phone")
        ledger.replenishTopTen(writer: "phone")
        XCTAssertNil(ledger.rankingPair) // 009 already beats every backlog item, including unrelated newcomers.
        XCTAssertEqual(ledger.rankedCaptureIDs.last, "009")
        XCTAssertTrue(ledger.topTenIsVerified)
    }

}
