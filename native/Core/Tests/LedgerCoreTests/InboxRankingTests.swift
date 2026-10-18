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
    func testCaptureArrivingMidSortIsRetainedAndRankedDuringTheCurrentSession() throws {
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
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair, pair)
        while ledger.inboxRanking?.topTen?.candidate?.item == "newer", let current = ledger.rankingPair {
            ledger.chooseCapture(current.first, from: current, writer: "phone")
        }
        XCTAssertEqual(ledger.rankingPair?.first, "newest")
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
        XCTAssertEqual(ledger.backlogCaptures.count, 9)
        XCTAssertTrue(ledger.backlogCaptures.contains { $0.id == "newest" })
        XCTAssertTrue(ledger.unrankedCaptures.isEmpty)
        XCTAssertFalse(ledger.rankingIsActive)
    }

    func testQualifyingIdeaFinishesPlacementBeforeTheNextUnseenIdea() throws {
        var ledger = try legacyRanked()
        let date = Date(timeIntervalSince1970: 100)
        for (index, id) in ["a", "b", "c"].enumerated() {
            try ledger.addCapture(text: id, id: id, writer: "phone", now: date.addingTimeInterval(Double(index)))
        }
        ledger.prepareRanking(writer: "phone")
        let threshold = try XCTUnwrap(ledger.rankingPair)
        XCTAssertEqual(threshold.first, "c"); XCTAssertEqual(threshold.second, "009")
        ledger.chooseCapture("c", from: threshold, writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "c")
        XCTAssertEqual(ledger.unseenCaptures.map(\.id), ["b", "a"])
        XCTAssertEqual(ledger.partiallyRankedCaptures.map(\.id), ["c"])
        XCTAssertTrue(ledger.inboxRanking?.topTen?.deferred?.isEmpty ?? true)
        // Pause and resume after each answer, including backup and companion
        // round trips. Never move to b until c has entered the top ten.
        var comparisons = 1
        while !ledger.rankedCaptureIDs.contains("c") {
            ledger = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
            var companion = Ledger(); companion.merge(ledger)
            XCTAssertEqual(companion.rankingPair, ledger.rankingPair)
            let current = try XCTUnwrap(ledger.rankingPair)
            ledger.prepareRanking(writer: "phone")
            XCTAssertEqual(ledger.rankingPair, current)
            XCTAssertEqual(current.first, "c")
            XCTAssertEqual(ledger.unseenCaptures.map(\.id), ["b", "a"])
            comparisons += 1
            guard comparisons <= 5 else { XCTFail("Too many comparisons"); return }
            ledger.chooseCapture("c", from: current, writer: "phone")
        }
        XCTAssertEqual(ledger.rankedCaptureIDs.first, "c")
        XCTAssertEqual(ledger.backlogCaptures.map(\.id), ["009"])
        XCTAssertEqual(ledger.rankingPair?.first, "b")
        XCTAssertEqual(ledger.unseenCaptures.map(\.id), ["a"])
        XCTAssertEqual(ledger.partiallyRankedCaptures.map(\.id), ["b"])
        XCTAssertFalse(ledger.topTenIsVerified)
    }

    func testContinueRanksNewestBeforeOlderPartialAndRestoresSavedBounds() throws {
        var ledger = try legacyRanked()
        let date = Date(timeIntervalSince1970: 100)
        try ledger.addCapture(text: "Older waiting", id: "waiting", writer: "phone", now: date)
        try ledger.addCapture(text: "Partly placed", id: "partial", writer: "phone", now: date.addingTimeInterval(1))
        ledger.prepareRanking(writer: "phone")
        let threshold = try XCTUnwrap(ledger.rankingPair)
        ledger.chooseCapture("partial", from: threshold, writer: "phone")
        let paused = try XCTUnwrap(ledger.rankingPair)
        XCTAssertNotEqual(paused.second, "009")
        let savedChoices = ledger.inboxRanking?.topTen?.preferences
        try ledger.addCapture(text: "Newest capture", id: "newest", writer: "watch", now: date.addingTimeInterval(2))
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair, paused) // Incoming data cannot replace a visible pair.
        ledger = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        var phone = Ledger(); phone.merge(ledger)
        phone.prepareRanking(writer: "phone")
        let newest = try XCTUnwrap(phone.rankingPair)
        XCTAssertEqual(newest.first, "newest"); XCTAssertEqual(newest.second, "009")
        XCTAssertEqual(phone.inboxRanking?.topTen?.preferences, savedChoices)
        phone.chooseCapture(newest.second, from: newest, writer: "phone")
        XCTAssertEqual(phone.rankingPair?.first, "partial")
        XCTAssertEqual(phone.rankingPair?.second, paused.second)
        var answers = 1 // The earlier win against #10 remains saved.
        while let pair = phone.rankingPair, pair.first == "partial" {
            answers += 1
            guard answers <= 5 else { XCTFail("Repeated previous comparisons"); return }
            phone.chooseCapture("partial", from: pair, writer: "phone")
        }
        XCTAssertEqual(phone.rankedCaptureIDs.first, "partial")
        XCTAssertEqual(phone.rankingPair?.first, "waiting")
        XCTAssertTrue(phone.backlogCaptures.contains { $0.id == "newest" })
        XCTAssertEqual(phone.captures.count, 13)
    }

    func testResumeIncludesReminderImportsByOriginalCreationDateRatherThanImportTime() throws {
        var ledger = try legacyRanked()
        let date = Date(timeIntervalSince1970: 100)
        try ledger.addCapture(text: "Paused", id: "paused", writer: "phone", now: date)
        ledger.prepareRanking(writer: "phone")
        try ledger.addCapture(text: "New native", id: "native", writer: "phone", now: date.addingTimeInterval(20))
        ledger.importReminders([
            ReminderSnapshot(identifiers: ["old"], title: "Imported late but created earlier", createdAt: date.addingTimeInterval(-10)),
            ReminderSnapshot(identifiers: ["new"], title: "Newest original reminder", createdAt: date.addingTimeInterval(30))
        ], writer: "phone", now: date.addingTimeInterval(1000))
        ledger.prepareRanking(writer: "phone")
        var order: [String] = []
        while let pair = ledger.rankingPair {
            order.append(pair.first)
            ledger.chooseCapture(pair.second, from: pair, writer: "phone")
        }
        XCTAssertEqual(order, ["reminder-new", "native", "paused", "reminder-old"])
        XCTAssertEqual(ledger.rankedCaptureIDs, (0..<10).map { String(format: "%03d", $0) })
    }

    func testContinuePrioritizesNewIdeasOverAnUnfinishedBacklogTournament() throws {
        var ledger = try legacyRanked()
        for id in ["011", "012", "013"] { try ledger.addCapture(text: id, id: id, writer: "phone") }
        try finish(&ledger)
        ledger.setCaptureDone(id: "000", done: true, writer: "phone")
        ledger.replenishTopTen(writer: "phone")
        let backlogPair = try XCTUnwrap(ledger.rankingPair)
        XCTAssertNotNil(ledger.inboxRanking?.priorityTournament)
        try ledger.addCapture(text: "New urgent candidate", id: "newest", writer: "watch")
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair, backlogPair)
        // This was the Top 10 section's Continue action: it must refresh too.
        ledger.replenishTopTen(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "newest")
        XCTAssertEqual(ledger.captures.count, 14)
        XCTAssertNotNil(ledger.inboxRanking?.priorityTournament) // Tournament answers remain reusable.
        try answerBatch(&ledger) { min($0.first, $0.second) }
        XCTAssertEqual(ledger.rankedCaptureIDs.count, 10)
        XCTAssertTrue(ledger.backlogCaptures.contains { $0.id == "newest" })
    }

    func testPartlyRankedNewerIdeaIsNotDelayedByOlderUnseenIdeas() throws {
        var ledger = try legacyRanked()
        let date = Date(timeIntervalSince1970: 100)
        try ledger.addCapture(text: "Recent partial", id: "recent", writer: "phone", now: date.addingTimeInterval(10))
        ledger.prepareRanking(writer: "phone")
        let pair = try XCTUnwrap(ledger.rankingPair)
        ledger.chooseCapture(pair.first, from: pair, writer: "phone")
        let partial = ledger.rankingPair
        ledger.importReminders([ReminderSnapshot(identifiers: ["old"], title: "Old unseen import", createdAt: date)], writer: "phone")
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, partial?.first)
        XCTAssertEqual(ledger.rankingPair?.second, partial?.second)
        XCTAssertEqual(ledger.unseenCaptures.map(\.id), ["reminder-old"])
    }

    func testReturnedSnoozeStillComesBeforeNewlyCreatedIdeasOnContinue() throws {
        var ledger = try legacyRanked()
        try ledger.addCapture(text: "Return later", id: "returning", writer: "phone", now: Date(timeIntervalSince1970: 1))
        ledger.snoozeCapture("returning", until: Date().addingTimeInterval(3600), writer: "phone")
        try ledger.addCapture(text: "Paused newer idea", id: "paused", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        let visible = ledger.rankingPair
        ledger.bringBackCapture("returning", writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, visible?.first)
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "returning")
        XCTAssertEqual(ledger.rankingPair?.second, "009")
        XCTAssertTrue(ledger.unrankedCaptures.contains { $0.id == "paused" })
    }

    func testPreviouslyDeferredWinnersKeepAnswersWhileNewerIdeasGoFirst() throws {
        var ledger = try legacyRanked()
        for (index, id) in ["winner", "unseen", "current"].enumerated() {
            try ledger.addCapture(text: id, id: id, writer: "phone", now: Date(timeIntervalSince1970: Double(100 + index)))
        }
        ledger.normalizeInboxRanking(writer: "phone")
        // This is the persisted state produced by build 32 after screening a
        // winner, moving it aside, and presenting a different candidate.
        ledger.inboxRanking?.topTen?.preferences.append(InboxPreference(winner: "winner", loser: "009"))
        ledger.inboxRanking?.topTen?.presented = ["winner", "current", "009"].sorted()
        ledger.inboxRanking?.topTen?.deferred = ["winner"]
        ledger.inboxRanking?.topTen?.pending = ["unseen"]
        let base = ledger.rankedCaptureIDs
        ledger.inboxRanking?.topTen?.candidate = TopTenInsertion(item: "current", base: base, high: base.count, screening: true)
        ledger = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        let active = try XCTUnwrap(ledger.rankingPair)
        ledger.prepareRanking(writer: "phone")
        let resumed = try XCTUnwrap(ledger.rankingPair)
        XCTAssertEqual(resumed.first, active.first)
        XCTAssertEqual(resumed.second, active.second)
        ledger.chooseCapture("009", from: resumed, writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "unseen")
        let unseen = try XCTUnwrap(ledger.rankingPair)
        ledger.chooseCapture(unseen.second, from: unseen, writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "winner")
        XCTAssertNotEqual(ledger.rankingPair?.second, "009") // The saved answer still counts.
        while let pair = ledger.rankingPair, pair.first == "winner" {
            ledger.chooseCapture("winner", from: pair, writer: "phone")
        }
        XCTAssertEqual(ledger.rankedCaptureIDs.first, "winner")
        XCTAssertNil(ledger.rankingPair)
        XCTAssertEqual(ledger.captures.count, 13)
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

    func testSequentialPlacementUsesAtMostFiveAnswersPerCandidateAsThresholdChanges() throws {
        var ledger = try legacyRanked()
        var scores: [String: Double] = [:]
        for i in 0..<20 {
            let id = "candidate-\(i)"
            scores[id] = Double(i) / 3 - 2
            try ledger.addCapture(text: id, id: id, writer: "phone", now: Date(timeIntervalSince1970: Double(i + 100)))
        }
        ledger.prepareRanking(writer: "phone")
        var answers: [String: Int] = [:]
        try answerBatch(&ledger) { pair in
            answers[pair.first, default: 0] += 1
            return (scores[pair.first] ?? Double(pair.first)!) < (scores[pair.second] ?? Double(pair.second)!) ? pair.first : pair.second
        }
        XCTAssertEqual(answers.count, 20)
        XCTAssertTrue(answers.values.allSatisfy { $0 <= 5 }, "\(answers)")
        XCTAssertTrue(ledger.topTenIsVerified)
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

    func testBackgroundAdvanceDoesNotMarkANeverDisplayedIdeaAsSeen() throws {
        var ledger = try legacyRanked()
        try ledger.addCapture(text: "Older unseen", id: "older", writer: "phone", now: Date(timeIntervalSince1970: 100))
        try ledger.addCapture(text: "Shown", id: "shown", writer: "phone", now: Date(timeIntervalSince1970: 200))
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.partiallyRankedCaptures.map(\.id), ["shown"])
        // Delete the current candidate outside the ranking screen. Advancing
        // the saved session is not evidence that the next candidate was seen.
        ledger.setCaptureDeleted("shown", deleted: true, writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "older")
        XCTAssertEqual(ledger.unseenCaptures.map(\.id), ["older"])
        XCTAssertTrue(ledger.partiallyRankedCaptures.isEmpty)
        ledger.markRankingPresented(writer: "phone")
        XCTAssertEqual(ledger.partiallyRankedCaptures.map(\.id), ["older"])
        XCTAssertTrue(ledger.unseenCaptures.isEmpty)
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
        // A continuous session now verifies replacements too, not just the
        // selected idea's provisional insertion. It may appear on either side.
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
        var answers = 0
        while let pair = ledger.rankingPair, pair.first == "011" {
            answers += 1
            guard answers <= 5 else { XCTFail("Too many insertion comparisons"); return }
            ledger.chooseCapture("011", from: pair, writer: "phone")
        }
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
        XCTAssertTrue(watch.backlogCaptures.contains { $0.id == "watch-new" })
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
