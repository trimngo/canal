import Foundation

/// One snapshot at a time. Edits made during delivery remain in the durable
/// ledger and are sent after completion; refreshing never cancels a transfer.
public struct CompanionDeliveryState {
    private var acknowledged: Data?
    private var active: (id: String, data: Data)?
    public init() {}

    public mutating func begin(_ data: Data, id: String) -> Bool {
        guard active == nil, data != acknowledged else { return false }
        active = (id, data)
        return true
    }

    public mutating func finish(id: String, succeeded: Bool) {
        guard let active, active.id == id else { return }
        if succeeded { acknowledged = active.data }
        self.active = nil
    }
}

/// Bounded recovery while the system allows execution. A foreground refresh
/// starts a new retry budget, including after the app was suspended offline.
public struct CompanionRetry {
    private var failures = 0
    public init() {}
    public mutating func reset() { failures = 0 }
    public mutating func nextDelay() -> UInt64? {
        guard failures < 6 else { return nil }
        let seconds = UInt64(min(60, 2 << failures))
        failures += 1
        return seconds
    }
}
