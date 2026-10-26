import XCTest
@testable import LedgerCore

final class CompanionQuickDeliveryTests: XCTestCase {
    func testRestartPreemptsAnInFlightLogAndLateReceiptCannotFinishNewTimerPacket() throws {
        var watch = Ledger(), quick = CompanionQuickDelivery()
        try watch.enqueueTimer(id: "timer", title: "Practice", duration: 300, writer: "watch", onWatch: true)
        let initial = try packet(&quick, ledger: watch, id: "initial")
        quick.finish(id: initial.id, saved: true)
        try sample(&watch, id: "reply")
        let log = try packet(&quick, ledger: watch, id: "log")
        watch.restartTimer(writer: "watch", onWatch: true)
        let restart = try packet(&quick, ledger: watch, id: "restart")
        XCTAssertEqual(restart.ledger.timerControl, watch.timerControl)
        XCTAssertTrue(restart.ledger.entries.isEmpty)
        XCTAssertFalse(quick.finish(id: log.id, saved: true))
        XCTAssertNil(try quick.prepare(watch, id: "still-in-flight"))
        XCTAssertTrue(quick.finish(id: restart.id, saved: true))
        XCTAssertFalse(quick.hasReceived(watch.entries[0]))
        let retry = try packet(&quick, ledger: watch, id: "reply-retry")
        XCTAssertEqual(retry.ledger.entries.map(\.id), ["reply"])
        XCTAssertTrue(quick.finish(id: retry.id, saved: true))
        XCTAssertTrue(quick.recentLogsReceived(in: watch))
    }

    func testRapidDoneActionsSupersedeOlderTimerMessagesAndCannotBeReverted() throws {
        var watch = Ledger(), phone = Ledger(), quick = CompanionQuickDelivery()
        try watch.enqueueTimer(id: "one", title: "First", duration: 300, writer: "watch", onWatch: true)
        try watch.enqueueTimer(id: "two", title: "Next", duration: 300, writer: "watch", onWatch: true)
        let first = try packet(&quick, ledger: watch, id: "first")
        watch.finishTimer(writer: "watch", onWatch: true)
        let next = try packet(&quick, ledger: watch, id: "next")
        watch.finishTimer(writer: "watch", onWatch: true)
        let stopped = try packet(&quick, ledger: watch, id: "stopped")
        XCTAssertFalse(quick.finish(id: first.id, saved: true))
        XCTAssertFalse(quick.finish(id: next.id, saved: true))
        phone.merge(stopped.ledger); phone.merge(next.ledger); phone.merge(first.ledger)
        XCTAssertNil(phone.currentTimer)
        XCTAssertTrue(phone.waitingTimers.isEmpty)
        XCTAssertEqual(phone.timerControl, watch.timerControl)
        XCTAssertTrue(quick.finish(id: stopped.id, saved: true))
    }

    func testTimerContextSnapshotIsBoundedAndPreservesCurrentTaskAndPeerSettings() throws {
        var watch = Ledger(), phone = Ledger()
        for index in 0..<50 {
            try watch.enqueueTimer(id: "timer-\(index)", title: String(repeating: "🦉", count: 500), duration: 300,
                writer: "watch", onWatch: true)
        }
        try sample(&watch, id: "private-log")
        try watch.addCapture(text: "Unrelated idea", writer: "watch")
        var settings = phone.settings; settings.use24HourTime = true
        try phone.saveSettings(settings, writer: "phone")
        let savedSettings = phone.settings
        let data = try XCTUnwrap(CompanionQuickDelivery.timerSnapshot(watch))
        XCTAssertLessThanOrEqual(data.count, 16_000)
        let snapshot = try JSONDecoder().decode(CompanionQuickPacket.self, from: data)
        XCTAssertEqual(snapshot.ledger.currentTimer, watch.currentTimer)
        XCTAssertTrue(snapshot.ledger.entries.isEmpty); XCTAssertTrue(snapshot.ledger.captures.isEmpty)
        XCTAssertTrue(snapshot.ledger.categories.isEmpty)
        phone.merge(snapshot.ledger)
        XCTAssertEqual(phone.currentTimer, watch.currentTimer)
        XCTAssertEqual(phone.settings, savedSettings)
        XCTAssertNil(try CompanionQuickDelivery.timerSnapshot(Ledger()))
    }

    func testTimerControlGetsPacketSpaceBeforeLargeSettingsAndHistory() throws {
        var watch = Ledger(), quick = CompanionQuickDelivery()
        watch.settings.urgencyPhrases = Array(repeating: String(repeating: "large preference ", count: 300), count: 20)
        let revision = watch.nextRevision(writer: "watch")
        watch.settings.revision = revision
        try watch.enqueueTimer(id: "timer", title: "Practice", duration: 300, writer: "watch", onWatch: true)
        try sample(&watch, id: "reply")
        let timer = try packet(&quick, ledger: watch, limit: 4_000)
        XCTAssertEqual(timer.ledger.timerControl, watch.timerControl)
        XCTAssertEqual(timer.ledger.currentTimer, watch.currentTimer)
        XCTAssertEqual(timer.ledger.settings.revision, Revision())
        XCTAssertTrue(timer.ledger.entries.isEmpty)
    }
    private func sample(_ ledger: inout Ledger, id: String, text: String = "Working") throws {
        try ledger.saveQuickSample(id: id, at: Date(), activity: text, writer: "watch")
    }
    private func packet(_ state: inout CompanionQuickDelivery, ledger: Ledger, id: String = "quick", limit: Int = 48_000) throws -> CompanionQuickPacket {
        let data = try XCTUnwrap(state.prepare(ledger, id: id, byteLimit: limit))
        XCTAssertLessThanOrEqual(data.count, limit)
        return try JSONDecoder().decode(CompanionQuickPacket.self, from: data)
    }

    func testNewLongWatchReplyBypassesAnOlderHistoryFileAndIsAcknowledgedAfterMerge() throws {
        var watch = Ledger(), phone = Ledger(), background = CompanionDeliveryState(), quick = CompanionQuickDelivery()
        for index in 0..<200 { try sample(&watch, id: "old-\(index)", text: String(repeating: "a", count: 490)) }
        let oldFile = try JSONEncoder().encode(watch)
        XCTAssertGreaterThan(oldFile.count, 48_000)
        XCTAssertTrue(background.begin(oldFile, id: "old-file"))
        try sample(&watch, id: "new-long", text: String(repeating: "🦉", count: 490))
        let latest = try XCTUnwrap(watch.entries.first { $0.id == "new-long" })
        let update = try packet(&quick, ledger: watch)
        XCTAssertTrue(update.ledger.entries.contains { $0.id == "new-long" })
        XCTAssertLessThan(update.ledger.entries.count, watch.entries.count)
        XCTAssertFalse(quick.hasReceived(latest))
        phone.merge(update.ledger)
        let disk = try JSONEncoder().encode(phone)
        phone = try JSONDecoder().decode(Ledger.self, from: disk)
        XCTAssertTrue(quick.finish(id: update.id, saved: true))
        XCTAssertTrue(quick.hasReceived(latest))
        XCTAssertEqual(phone.entries.first { $0.id == "new-long" }?.activity, latest.activity)
        // The original queued file can arrive afterwards without losing or
        // duplicating the entry delivered through the fast lane.
        phone.merge(try JSONDecoder().decode(Ledger.self, from: oldFile))
        XCTAssertEqual(phone.entries.count, 201)
        XCTAssertEqual(phone.entries.filter { $0.id == "new-long" }.count, 1)
    }

    func testFailureDoesNotAcknowledgeAndRetryIncludesChangesSavedWhileInFlight() throws {
        var watch = Ledger(), quick = CompanionQuickDelivery()
        try sample(&watch, id: "one")
        let one = try packet(&quick, ledger: watch, id: "one")
        XCTAssertNil(try quick.prepare(watch, id: "blocked"))
        try sample(&watch, id: "two")
        XCTAssertFalse(quick.finish(id: "unrelated", saved: true))
        XCTAssertNil(try quick.prepare(watch, id: "still-blocked"))
        XCTAssertFalse(quick.finish(id: one.id, saved: false))
        XCTAssertFalse(quick.recentLogsReceived(in: watch))
        let retry = try packet(&quick, ledger: watch, id: "retry")
        XCTAssertEqual(Set(retry.ledger.entries.map(\.id)), ["one", "two"])
        XCTAssertTrue(quick.finish(id: retry.id, saved: true))
        XCTAssertTrue(quick.recentLogsReceived(in: watch))
        XCTAssertNil(try quick.prepare(watch, id: "duplicate"))
    }

    func testLateReceiptCannotAcknowledgeAnEditOrFinishANewerTransfer() throws {
        var watch = Ledger(), quick = CompanionQuickDelivery()
        try sample(&watch, id: "one")
        _ = try packet(&quick, ledger: watch, id: "old")
        try watch.saveSample(id: "one", at: watch.entries[0].end, activity: "Edited reply", categoryID: nil, writer: "watch")
        XCTAssertTrue(quick.finish(id: "old", saved: true))
        XCTAssertFalse(quick.hasReceived(watch.entries[0]))
        _ = try packet(&quick, ledger: watch, id: "new")
        XCTAssertFalse(quick.finish(id: "old", saved: true))
        XCTAssertNil(try quick.prepare(watch, id: "cannot-replace-new"))
        XCTAssertTrue(quick.finish(id: "new", saved: true))
        XCTAssertTrue(quick.hasReceived(watch.entries[0]))
    }

    func testOversizedIdeaDoesNotBlockLogsAndRemainsInFullBackup() throws {
        var watch = Ledger(), quick = CompanionQuickDelivery()
        try watch.addCapture(text: "Large idea", id: "large", writer: "watch")
        try watch.updateCaptureText(id: "large", text: String(repeating: "Long idea\n", count: 10_000), writer: "watch")
        try sample(&watch, id: "reply")
        let update = try packet(&quick, ledger: watch, limit: 4_000)
        XCTAssertEqual(update.ledger.entries.map(\.id), ["reply"])
        XCTAssertTrue(update.ledger.captures.isEmpty)
        quick.finish(id: update.id, saved: true)
        XCTAssertFalse(quick.recentLogsReceived(in: watch))
        XCTAssertNil(try quick.prepare(watch, id: "oversize-only", byteLimit: 4_000))
        let restored = try LedgerBackup.decode(LedgerBackup(ledger: watch).encoded()).ledger
        XCTAssertEqual(restored.captures, watch.captures)
    }

    func testImmediateEditsDeletionRestoreAndIdeasReuseExistingMergeWithoutChangingSettings() throws {
        var watch = Ledger(), phone = Ledger(), quick = CompanionQuickDelivery()
        try sample(&watch, id: "reply")
        try watch.addCapture(text: "Idea", id: "idea", writer: "watch")
        var settings = phone.settings; settings.use24HourTime = true
        try phone.saveSettings(settings, writer: "phone")
        let preserved = phone.settings
        let first = try packet(&quick, ledger: watch, id: "first")
        phone.merge(first.ledger); quick.finish(id: first.id, saved: true)
        XCTAssertEqual(phone.settings, preserved)
        XCTAssertEqual(phone.captures.map(\.id), ["idea"])
        watch.setLogDeleted("reply", deleted: true, writer: "watch")
        watch.setCaptureDeleted("idea", deleted: true, writer: "watch")
        let removed = try packet(&quick, ledger: watch, id: "removed")
        phone.merge(removed.ledger); quick.finish(id: removed.id, saved: true)
        XCTAssertTrue(phone.activeEntries.isEmpty)
        XCTAssertTrue(phone.activeCaptures.isEmpty)
        watch.setLogDeleted("reply", deleted: false, writer: "watch")
        watch.setCaptureDeleted("idea", deleted: false, writer: "watch")
        let restored = try packet(&quick, ledger: watch, id: "restored")
        phone.merge(restored.ledger)
        XCTAssertEqual(phone.activeEntries.map(\.id), ["reply"])
        XCTAssertEqual(phone.activeCaptures.map(\.id), ["idea"])
        XCTAssertEqual(phone.settings, preserved)
    }

    func testSettingsOnlyChangeBypassesHistoryAndDoesNotRepeatAfterAcknowledgment() throws {
        var phone = Ledger(), watch = Ledger(), quick = CompanionQuickDelivery()
        XCTAssertNil(try quick.prepare(phone, id: "seed"))
        var settings = phone.settings
        settings.notificationsEnabled = true; settings.notificationDelivery = .automatic
        settings.notificationTiming = .randomized; settings.randomizedNotificationInterval = 30
        try phone.saveSettings(settings, writer: "phone")
        let update = try packet(&quick, ledger: phone)
        XCTAssertTrue(update.ledger.entries.isEmpty); XCTAssertTrue(update.ledger.captures.isEmpty)
        XCTAssertEqual(update.ledger.settings, phone.settings)
        watch.merge(update.ledger)
        XCTAssertEqual(watch.settings, phone.settings)
        XCTAssertTrue(quick.finish(id: update.id, saved: true))
        XCTAssertNil(try quick.prepare(phone, id: "duplicate"))
        XCTAssertEqual(try LedgerBackup.decode(LedgerBackup(ledger: watch).encoded()).ledger.settings, phone.settings)
    }

    func testSettingsRetryTakesLatestPreferenceAndOlderBackgroundFilesCannotRevertIt() throws {
        var phone = Ledger(), quick = CompanionQuickDelivery()
        var settings = phone.settings; settings.notificationsEnabled = true; settings.notificationDelivery = .watch
        try phone.saveSettings(settings, writer: "phone")
        let oldFile = try JSONEncoder().encode(phone)
        let old = try packet(&quick, ledger: phone, id: "old")
        settings.notificationDelivery = .automatic
        try phone.saveSettings(settings, writer: "phone")
        XCTAssertFalse(quick.finish(id: old.id, saved: false))
        let latest = try packet(&quick, ledger: phone, id: "latest")
        var watch = Ledger(); watch.merge(latest.ledger)
        watch.merge(try JSONDecoder().decode(Ledger.self, from: oldFile))
        XCTAssertEqual(watch.settings.notificationDelivery, .automatic)
        XCTAssertEqual(watch.settings.revision, phone.settings.revision)
        quick.finish(id: latest.id, saved: true)
        var returned = watch.settings; returned.notificationsEnabled = false
        try watch.saveSettings(returned, writer: "watch")
        var watchQuick = CompanionQuickDelivery()
        phone.merge(try packet(&watchQuick, ledger: watch).ledger)
        XCTAssertFalse(phone.settings.notificationsEnabled)
        XCTAssertEqual(phone.settings.notificationDelivery, .automatic)
    }

    func testSettingsSavedWhilePacketIsInFlightAreSentNextWithoutLosingLogs() throws {
        var phone = Ledger(), quick = CompanionQuickDelivery()
        var settings = phone.settings; settings.notificationsEnabled = true
        try phone.saveSettings(settings, writer: "phone")
        try sample(&phone, id: "reply")
        let first = try packet(&quick, ledger: phone, id: "first")
        settings.notificationDelivery = .watch; try phone.saveSettings(settings, writer: "phone")
        quick.finish(id: first.id, saved: true)
        XCTAssertTrue(quick.recentLogsReceived(in: phone))
        let next = try packet(&quick, ledger: phone, id: "next")
        XCTAssertEqual(next.ledger.settings.notificationDelivery, .watch)
        XCTAssertTrue(next.ledger.entries.isEmpty)
        var oldPeer = Ledger(); oldPeer.merge(first.ledger); oldPeer.merge(next.ledger)
        XCTAssertEqual(oldPeer.entries.map(\.id), ["reply"])
        XCTAssertEqual(oldPeer.settings, phone.settings)
    }
}
