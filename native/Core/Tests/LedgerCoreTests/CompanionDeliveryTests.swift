import XCTest
@testable import LedgerCore

final class CompanionDeliveryTests: XCTestCase {
    private func snapshot(_ ledger: Ledger) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(ledger)
    }

    func testOfflineEditsWaitForTheInFlightSnapshotThenReachTheOtherDevice() throws {
        var watch = Ledger(), phone = Ledger(), delivery = CompanionDeliveryState()
        try watch.saveQuickSample(id: "first", at: Date().addingTimeInterval(-60), activity: "Reading", writer: "watch")
        let first = try snapshot(watch)
        XCTAssertTrue(delivery.begin(first, id: "one"))
        try watch.saveQuickSample(id: "second", at: Date(), activity: "Walking", writer: "watch")
        let latest = try snapshot(watch)
        XCTAssertFalse(delivery.begin(latest, id: "two"))
        phone.merge(try JSONDecoder().decode(Ledger.self, from: first))
        delivery.finish(id: "one", succeeded: true)
        XCTAssertTrue(delivery.begin(latest, id: "two"))
        phone.merge(try JSONDecoder().decode(Ledger.self, from: latest))
        delivery.finish(id: "two", succeeded: true)
        XCTAssertEqual(Set(phone.entries.map(\.id)), ["first", "second"])
        XCTAssertFalse(delivery.begin(latest, id: "unnecessary-refresh"))
    }

    func testFailedDeliveryRetriesTheNewestDurableLedgerWithoutLosingSamples() throws {
        var watch = Ledger(), delivery = CompanionDeliveryState()
        try watch.saveQuickSample(id: "first", at: Date().addingTimeInterval(-60), activity: "Working", writer: "watch")
        XCTAssertTrue(delivery.begin(try snapshot(watch), id: "failed"))
        try watch.saveQuickSample(id: "second", at: Date(), activity: "Lunch", writer: "watch")
        let restored = try JSONDecoder().decode(Ledger.self, from: snapshot(watch))
        delivery.finish(id: "failed", succeeded: false)
        XCTAssertTrue(delivery.begin(try snapshot(restored), id: "retry"))
        XCTAssertEqual(restored.entries.count, 2)
    }

    func testFailedSnapshotIsNotAcknowledgedAndStaleCallbackCannotFinishANewerTransfer() {
        var delivery = CompanionDeliveryState()
        let data = Data("snapshot".utf8)
        XCTAssertTrue(delivery.begin(data, id: "failed"))
        delivery.finish(id: "failed", succeeded: false)
        XCTAssertTrue(delivery.begin(data, id: "retry"))
        delivery.finish(id: "failed", succeeded: true)
        XCTAssertFalse(delivery.begin(Data("newer".utf8), id: "blocked"))
        delivery.finish(id: "retry", succeeded: true)
        XCTAssertFalse(delivery.begin(data, id: "duplicate"))
    }

    func testRecoveryBacksOffAndForegroundRefreshRestartsAnExhaustedBudget() {
        var retry = CompanionRetry()
        XCTAssertEqual((0..<6).compactMap { _ in retry.nextDelay() }, [2, 4, 8, 16, 32, 60])
        XCTAssertNil(retry.nextDelay())
        retry.reset()
        XCTAssertEqual(retry.nextDelay(), 2)
    }
}
