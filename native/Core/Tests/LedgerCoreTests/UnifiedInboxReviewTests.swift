import XCTest
@testable import LedgerCore

final class UnifiedInboxReviewTests: XCTestCase {
    private func ranked(_ count: Int = 16) throws -> Ledger {
        var ledger = Ledger(), ranking = InboxRanking()
        for index in 0..<count {
            let id = String(format: "%03d", index)
            try ledger.addCapture(text: id, id: id, writer: "old-phone", now: Date(timeIntervalSince1970: Double(index)))
            if index < 10 { ranking.ordered.append(id) }
            else {
                if ranking.topTen == nil { ranking.topTen = TopTenRanking() }
                ranking.topTen?.backlog.append(id)
                ranking.topTen?.preferences.append(InboxPreference(winner: "009", loser: id))
            }
        }
        ranking.revision = ledger.nextRevision(writer: "old-phone")
        ledger.inboxRanking = ranking
        return ledger
    }
    @discardableResult
    private func finish(_ ledger: inout Ledger, prefer: (RankingPair) -> String = { min($0.first, $0.second) }) throws -> Int {
        var answers = 0, asked = Set<String>()
        while let pair = ledger.rankingPair {
            answers += 1
            guard answers < 2000 else { XCTFail("Review did not finish"); return answers }
            let key = [pair.first, pair.second].sorted().joined(separator: ":")
            XCTAssertTrue(asked.insert(key).inserted, "Repeated a saved comparison: \(key)")
            ledger.chooseCapture(prefer(pair), from: pair, writer: "phone")
            let restored = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
            XCTAssertEqual(restored.rankingPair, ledger.rankingPair)
            ledger = restored
        }
        return answers
    }

    func testNewestArrivalAppearsFirstEvenWhenGrowingAnOldTreePastCapacity() throws {
        var ledger = try ranked(32)
        ledger.prepareRanking(writer: "phone")
        ledger.setCaptureDone(id: "000", done: true, writer: "phone")
        ledger.prepareRanking(writer: "phone")
        XCTAssertNotNil(ledger.rankingPair)
        try ledger.addCapture(text: "Newest", id: "new", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "new")
        XCTAssertNil(ledger.inboxRanking?.topTen?.candidate)
        XCTAssertNil(ledger.inboxRanking?.topTen?.tournament)
        try finish(&ledger)
        XCTAssertEqual(ledger.rankedCaptureIDs, (1...10).map { String(format: "%03d", $0) })
        XCTAssertTrue(ledger.topTenIsVerified)
    }

    func testBackgroundArrivalPreservesQuestionThenNextAnswerReviewsNewest() throws {
        var ledger = try ranked()
        try ledger.addCapture(text: "Already reviewing", id: "old-candidate", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        let visible = try XCTUnwrap(ledger.rankingPair)
        let state = ledger.inboxRanking
        try ledger.addCapture(text: "New arrival", id: "new", writer: "watch", now: Date().addingTimeInterval(1))
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair, visible)
        XCTAssertEqual(ledger.inboxRanking, state)
        ledger.chooseCapture(min(visible.first, visible.second), from: visible, writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "new")
        try finish(&ledger)
        XCTAssertEqual(ledger.captures.count, 18)
    }

    func testExplicitReviewRefreshesPausedQuestionButRetainsAnswersAcrossSyncAndBackup() throws {
        var phone = try ranked()
        try phone.addCapture(text: "Older pending", id: "older", writer: "phone")
        phone.prepareRanking(writer: "phone")
        let pair = try XCTUnwrap(phone.rankingPair)
        phone.chooseCapture(min(pair.first, pair.second), from: pair, writer: "phone")
        let preferences = phone.inboxRanking?.topTen?.preferences
        try phone.addCapture(text: "Newest", id: "newest", writer: "watch", now: Date().addingTimeInterval(2))
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: phone).encoded()).ledger
        var watch = Ledger(); watch.merge(restored)
        watch.prepareRanking(writer: "watch")
        XCTAssertEqual(watch.rankingPair?.first, "newest")
        XCTAssertEqual(watch.inboxRanking?.topTen?.preferences, preferences)
        try finish(&watch)
        XCTAssertEqual(watch.rankedCaptureIDs, (0..<10).map { String(format: "%03d", $0) })
    }

    func testLegacyPartialCandidateBecomesTournamentAndRetainsItsAnsweredBounds() throws {
        var ledger = try ranked(10)
        try ledger.addCapture(text: "Partial", id: "004a", writer: "phone")
        let original = ledger.captures
        let base = ledger.inboxRanking!.ordered
        ledger.inboxRanking?.topTen = TopTenRanking(candidate: TopTenInsertion(item: "004a", base: base, low: 3, high: 6, screening: false), pending: ["004a"])
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertEqual(ledger.inboxRanking?.tournamentVersion, 1)
        XCTAssertNil(ledger.inboxRanking?.topTen?.candidate)
        let saved = ledger.inboxRanking?.topTen?.preferences ?? []
        XCTAssertTrue(saved.contains(InboxPreference(winner: "002", loser: "004a")))
        XCTAssertTrue(saved.contains(InboxPreference(winner: "004a", loser: "006")))
        try finish(&ledger)
        XCTAssertEqual(ledger.rankedCaptureIDs, ["000", "001", "002", "003", "004", "004a", "005", "006", "007", "008"])
        XCTAssertEqual(ledger.captures, original)
        XCTAssertTrue(ledger.topTenIsVerified)
    }

    func testLegacyDeferredAndPendingIdeasRemainAvailableInUnifiedTournament() throws {
        var ledger = try ranked(10)
        try ledger.addCapture(text: "Deferred", id: "deferred", writer: "phone")
        try ledger.addCapture(text: "Pending", id: "pending", writer: "phone")
        ledger.inboxRanking?.topTen = TopTenRanking(preferences: [InboxPreference(winner: "deferred", loser: "009")], pending: ["pending"], deferred: ["deferred"])
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertNil(ledger.inboxRanking?.topTen?.deferred)
        XCTAssertEqual(ledger.captures.count, 12)
        try finish(&ledger) { pair in
            if pair.first == "deferred" || pair.second == "deferred" { return "deferred" }
            return min(pair.first, pair.second)
        }
        XCTAssertEqual(ledger.rankedCaptureIDs.first, "deferred")
        XCTAssertTrue(ledger.backlogCaptures.contains { $0.id == "pending" })
    }

    func testRerankUsesTournamentForBacklogAndPreservesOtherPriorities() throws {
        var ledger = try ranked()
        ledger.prepareRanking(writer: "phone")
        let old = ledger.rankedCaptureIDs
        ledger.rerankCapture("015", writer: "phone")
        XCTAssertNil(ledger.inboxRanking?.topTen?.candidate)
        try finish(&ledger) { pair in
            if pair.first == "015" || pair.second == "015" { return "015" }
            return min(pair.first, pair.second)
        }
        XCTAssertEqual(ledger.rankedCaptureIDs, ["015"] + old.dropLast())
        ledger.setCaptureDone(id: "015", done: true, writer: "phone")
        ledger.prepareRanking(writer: "phone")
        try finish(&ledger)
        XCTAssertEqual(ledger.rankedCaptureIDs, old)
    }

    func testUnseenAndSeenRemainSeparateWithoutMarkingBackgroundQuestionsAsSeen() throws {
        var ledger = try ranked()
        try ledger.addCapture(text: "Seen", id: "seen", writer: "phone")
        ledger.prepareRanking(writer: "phone")
        XCTAssertTrue(ledger.partiallyRankedCaptures.contains { $0.id == "seen" })
        try ledger.addCapture(text: "Never displayed", id: "new", writer: "phone", now: Date().addingTimeInterval(1))
        ledger.normalizeInboxRanking(writer: "phone")
        XCTAssertTrue(ledger.unseenCaptures.contains { $0.id == "new" })
        let saved = try LedgerBackup.decode(LedgerBackup(ledger: ledger).encoded()).ledger
        XCTAssertEqual(saved.inboxSnapshot, ledger.inboxSnapshot)
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "new")
        XCTAssertTrue(ledger.partiallyRankedCaptures.contains { $0.id == "new" })
    }

    func testReturnAtEightJoinsOrdinaryArrivalOrderWithoutChangingCreationDate() throws {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: Date()))!
        let seven = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day)!
        let eight = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        var ledger = Ledger()
        try ledger.addCapture(text: "Before", id: "seven", writer: "phone", now: seven)
        try ledger.addCapture(text: "After", id: "nine", writer: "phone", now: nine)
        let original = day.addingTimeInterval(-86400)
        try ledger.addCapture(text: "Returning", id: "returned", writer: "phone", now: original)
        ledger.snoozeCapture("returned", until: day, writer: "phone", now: original)
        XCTAssertEqual(ledger.unrankedCaptures.map(\.id), ["nine", "returned", "seven"])
        let returned = try XCTUnwrap(ledger.captures.first { $0.id == "returned" })
        XCTAssertEqual(returned.createdAt, original)
        XCTAssertEqual(returned.rankingArrivalDate(), eight)
        XCTAssertTrue(returned.isSnoozed(at: eight.addingTimeInterval(-1)))
        XCTAssertFalse(returned.isSnoozed(at: eight))
        ledger.prepareRanking(writer: "phone")
        XCTAssertEqual(ledger.rankingPair?.first, "nine")
    }

    func testEightAMReturnUsesLocalCalendarAcrossDaylightSavingChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        for components in [DateComponents(year: 2026, month: 3, day: 29), DateComponents(year: 2026, month: 10, day: 25)] {
            let day = calendar.date(from: components)!
            var idea = Capture(text: "Return", createdAt: day.addingTimeInterval(-86400), revision: Revision())
            idea.snoozedUntil = day
            let arrival = try XCTUnwrap(idea.snoozeReturnDate(calendar: calendar))
            XCTAssertEqual(calendar.component(.hour, from: arrival), 8)
            XCTAssertEqual(calendar.component(.day, from: arrival), components.day)
            XCTAssertFalse(idea.isSnoozed(at: arrival, calendar: calendar))
        }
    }

    func testSearchFindsTitlesAndNotesAcrossListsWithoutChangingOrRankingAnything() throws {
        var ledger = try ranked()
        try ledger.updateCapture(id: "000", text: "Bicycle repair", notes: "Change wheels", writer: "phone")
        try ledger.updateCapture(id: "001", text: "Café idea", notes: "Ask María", writer: "phone")
        ledger.setCaptureReference("001", reference: true, writer: "phone")
        try ledger.updateCapture(id: "002", text: "Completed repair", notes: "Bicycle", writer: "phone")
        ledger.setCaptureDone(id: "002", done: true, writer: "phone")
        try ledger.updateCapture(id: "003", text: "Bicycle later", notes: "", writer: "phone")
        ledger.snoozeCapture("003", until: Date().addingTimeInterval(86400), writer: "phone")
        ledger.setCaptureDeleted("004", deleted: true, writer: "phone")
        let original = ledger
        XCTAssertEqual(Set(ledger.searchInbox("BICYCLE").map(\.id)), ["000", "002", "003"])
        XCTAssertEqual(ledger.searchInbox("repair wheels").map(\.id), ["000"])
        XCTAssertEqual(ledger.searchInbox("cafe maria").map(\.id), ["001"])
        XCTAssertTrue(ledger.searchInbox("not present").isEmpty)
        XCTAssertFalse(ledger.searchInbox("").contains { $0.id == "004" })
        XCTAssertEqual(ledger, original)
    }
}
