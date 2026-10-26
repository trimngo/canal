import Foundation

/// A bounded fast lane for recent logs, ideas, and revised settings. Full
/// history still travels through the existing durable file-transfer queue.
public struct CompanionQuickPacket: Codable, Sendable {
    public var id: String
    public var ledger: Ledger
}

public struct CompanionQuickReceipt: Codable, Sendable {
    public var id: String
    public var saved: Bool
    public init(id: String, saved: Bool) { self.id = id; self.saved = saved }
}

public struct CompanionQuickDelivery {
    private var acknowledged: [String: Revision] = [:]
    private var active: CompanionQuickPacket?
    public init() {}

    private func recent(_ source: Ledger) -> Ledger {
        var result = Ledger(); result.categories = []
        result.settings = source.settings
        result.timerControl = source.timerControl
        result.timerQueueOrder = source.timerQueueOrder
        var timers = Array((source.queuedTimers ?? []).sorted { $0.revision > $1.revision }.prefix(20))
        if let current = source.currentTimer, !timers.contains(where: { $0.id == current.id }) { timers.append(current) }
        result.queuedTimers = timers.isEmpty ? nil : timers
        result.datedGoals = Array((source.datedGoals ?? []).sorted { $0.revision > $1.revision }.prefix(20))
        result.calendarEvents = Array((source.calendarEvents ?? []).sorted { $0.revision > $1.revision }.prefix(20))
        result.entries = Array(source.entries.sorted { $0.revision == $1.revision ? $0.id < $1.id : $0.revision > $1.revision }.prefix(20))
        result.captures = Array(source.captures.sorted { $0.revision == $1.revision ? $0.id < $1.id : $0.revision > $1.revision }.prefix(20))
        result.logDeletions = Array((source.logDeletions ?? []).sorted { $0.revision > $1.revision }.prefix(20))
        return result
    }
    private func revisions(_ ledger: Ledger, includingSettings: Bool = true) -> [String: Revision] {
        var result: [String: Revision] = [:]
        if includingSettings, ledger.settings.revision > Revision() { result["settings"] = ledger.settings.revision }
        if let control = ledger.timerControl { result["timer-control"] = control.revision }
        if let order = ledger.timerQueueOrder { result["timer-order"] = order.revision }
        for timer in ledger.queuedTimers ?? [] { result["timer:" + timer.id] = timer.revision }
        for goal in ledger.datedGoals ?? [] { result["goal:" + goal.id] = goal.revision }
        for event in ledger.calendarEvents ?? [] { result["event:" + event.id] = event.revision }
        for entry in ledger.entries { result["log:" + entry.id] = entry.revision }
        for capture in ledger.captures { result["idea:" + capture.id] = capture.revision }
        for deletion in ledger.logDeletions ?? [] { result["deletion:" + deletion.id] = deletion.revision }
        return result
    }
    public func hasReceived(_ entry: CheckIn) -> Bool { acknowledged["log:" + entry.id] == entry.revision }
    public func recentLogsReceived(in ledger: Ledger) -> Bool {
        let wanted = revisions(recent(ledger), includingSettings: false)
        return !wanted.isEmpty && wanted.allSatisfy { acknowledged[$0.key] == $0.value }
    }

    /// Latest timer state also travels through application context, independently
    /// of interactive reachability and queued history files. Use the same wire
    /// packet so older receivers can still handle the interactive path.
    public static func timerSnapshot(_ source: Ledger, byteLimit: Int = 16_000) throws -> Data? {
        guard source.timerControl != nil else { return nil }
        var timer = Ledger(); timer.categories = []
        timer.timerControl = source.timerControl
        timer.queuedTimers = source.queuedTimers
        var delivery = CompanionQuickDelivery()
        return try delivery.prepare(timer, id: "timer-state", byteLimit: byteLimit)
    }

    public mutating func prepare(_ source: Ledger, id: String, byteLimit: Int = 48_000) throws -> Data? {
        if let active {
            // A Restart/Done/Pause must not wait for a previous log receipt or
            // its 15-second timeout. Old callbacks cannot finish this new packet.
            let sent = active.ledger.timerControl?.revision ?? acknowledged["timer-control"] ?? Revision()
            guard let control = source.timerControl, control.revision > sent else { return nil }
            self.active = nil
        }
        let latest = recent(source)
        var partial = Ledger(); partial.categories = []
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        func fits(_ value: Ledger) throws -> Bool { try encoder.encode(CompanionQuickPacket(id: id, ledger: value)).count <= byteLimit }
        let timerChanged = latest.timerControl.map { acknowledged["timer-control"] != $0.revision } ?? false
        // Send individual changes, never the full history ahead of a new reply.
        // Timer control and its active task travel together, ahead of all other
        // data, including large custom settings.
        if let control = latest.timerControl, acknowledged["timer-control"] != control.revision {
            let before = partial
            partial.timerControl = control
            partial.queuedTimers = latest.currentTimer.map { [$0] }
            if try !fits(partial) { partial = before }
        }
        // Seed settings cannot overwrite a peer's saved preference.
        if latest.settings.revision > Revision(), acknowledged["settings"] != latest.settings.revision {
            partial.settings = latest.settings
            if try !fits(partial) { partial.settings = Settings() }
        }
        if let order = latest.timerQueueOrder, acknowledged["timer-order"] != order.revision {
            partial.timerQueueOrder = order
            if try !fits(partial) { partial.timerQueueOrder = nil }
        }
        for item in latest.queuedTimers ?? [] where acknowledged["timer:" + item.id] != item.revision && partial.queuedTimers?.contains(where: { $0.id == item.id }) != true {
            partial.queuedTimers = (partial.queuedTimers ?? []) + [item]
            if try !fits(partial) { partial.queuedTimers?.removeLast() }
        }
        // A timer action gets a small packet first. Receipt immediately drains
        // the remaining logs and settings in the next packet, without losing
        // their acknowledgments or durable background delivery.
        for entry in latest.entries where !timerChanged && !hasReceived(entry) {
            partial.entries.append(entry)
            if try !fits(partial) { partial.entries.removeLast() }
        }
        for item in latest.captures where !timerChanged && acknowledged["idea:" + item.id] != item.revision {
            partial.captures.append(item)
            if try !fits(partial) { partial.captures.removeLast() }
        }
        for item in latest.logDeletions ?? [] where !timerChanged && acknowledged["deletion:" + item.id] != item.revision {
            partial.logDeletions = (partial.logDeletions ?? []) + [item]
            if try !fits(partial) { partial.logDeletions?.removeLast() }
        }
        for item in latest.datedGoals ?? [] where !timerChanged && acknowledged["goal:" + item.id] != item.revision {
            partial.datedGoals = (partial.datedGoals ?? []) + [item]
            if try !fits(partial) { partial.datedGoals?.removeLast() }
        }
        for item in latest.calendarEvents ?? [] where !timerChanged && acknowledged["event:" + item.id] != item.revision {
            partial.calendarEvents = (partial.calendarEvents ?? []) + [item]
            if try !fits(partial) { partial.calendarEvents?.removeLast() }
        }
        guard !revisions(partial).isEmpty else { return nil }
        let packet = CompanionQuickPacket(id: id, ledger: partial)
        active = packet
        return try encoder.encode(packet)
    }
    @discardableResult
    public mutating func finish(id: String, saved: Bool) -> Bool {
        guard let packet = active, packet.id == id else { return false }
        if saved { acknowledged.merge(revisions(packet.ledger)) { _, new in new } }
        active = nil
        return saved
    }
}
