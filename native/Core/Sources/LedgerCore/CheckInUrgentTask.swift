import Foundation

/// A notification preview of an existing task, independent of ranking/categories.
public struct CheckInUrgentTask: Codable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let dueAt: Date?
    public let availableAt: Date?
    public let createdAt: Date

    public static func candidates(in ledger: Ledger) -> [Self] {
        ledger.captures.compactMap { capture in
            guard capture.deletedAt == nil, !capture.isDone, capture.isReference != true,
                  let urgency = ledger.urgency(for: capture) else { return nil }
            return Self(id: capture.id, text: capture.text, dueAt: urgency.timing.dueAt,
                        availableAt: capture.snoozeReturnDate(), createdAt: capture.createdAt)
        }
    }

    /// Unseen tasks get a turn first, ordered by deadline. After that, time
    /// since an appearance is weighted 3x for overdue and 2x for due-in-24h.
    /// Never show the same task consecutively when another is available.
    public static func next(from candidates: [Self], lastShown: [String: Date], at date: Date) -> Self? {
        let available = candidates.filter { $0.availableAt.map { $0 <= date } ?? true }
        var mostRecent: String?
        var latest = Date.distantPast
        for task in available {
            guard let shown = lastShown[task.id] else { continue }
            if shown > latest || (shown == latest && task.id > (mostRecent ?? "")) {
                mostRecent = task.id; latest = shown
            }
        }
        let eligible = available.count > 1 ? available.filter { $0.id != mostRecent } : available
        return eligible.sorted { a, b in
            let aLast = lastShown[a.id], bLast = lastShown[b.id]
            if (aLast == nil) != (bLast == nil) { return aLast == nil }
            if let aLast, let bLast {
                let aScore = max(0, date.timeIntervalSince(aLast)) * a.weight(at: date)
                let bScore = max(0, date.timeIntervalSince(bLast)) * b.weight(at: date)
                if aScore != bScore { return aScore > bScore }
            }
            if a.dueAt != b.dueAt { return (a.dueAt ?? .distantFuture) < (b.dueAt ?? .distantFuture) }
            return a.createdAt == b.createdAt ? a.id < b.id : a.createdAt < b.createdAt
        }.first
    }

    private func weight(at date: Date) -> Double {
        guard let dueAt else { return 1 }
        if dueAt <= date { return 3 }
        return dueAt.timeIntervalSince(date) <= 86400 ? 2 : 1
    }

    public var preview: String {
        // Reminders imports can contain title + notes. Surface the task title.
        text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? text
    }
}

/// Local notification history. Future assignments are kept separately: building
/// or refreshing a queue must never count future notifications as already shown.
/// An elapsed scheduled slot is an appearance, not proof the user read an alert.
public struct CheckInUrgentHistory: Codable, Equatable, Sendable {
    public enum Repetition: String, Codable, Sendable { case hourly, daily }
    public struct Appearance: Codable, Equatable, Sendable {
        public let taskID: String
        public let date: Date
        public let repetition: Repetition?
        public init(taskID: String, date: Date, repetition: Repetition?) {
            self.taskID = taskID; self.date = date; self.repetition = repetition
        }
    }
    public private(set) var lastShown: [String: Date] = [:]
    public private(set) var scheduled: [String: Appearance] = [:]
    public init() {}

    public mutating func reconcile(at now: Date, calendar: Calendar = .current) {
        for appearance in scheduled.values where appearance.date <= now {
            var date = appearance.date
            if let repetition = appearance.repetition {
                let fields: Set<Calendar.Component> = repetition == .hourly ? [.minute, .second] : [.hour, .minute, .second]
                let clock = calendar.dateComponents(fields, from: date)
                if let latest = calendar.nextDate(after: now.addingTimeInterval(1), matching: clock,
                                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first,
                                                 direction: .backward), latest >= date { date = latest }
            }
            lastShown[appearance.taskID] = max(lastShown[appearance.taskID] ?? .distantPast, date)
        }
    }

    public mutating func schedule(requestID: String, taskID: String?, at date: Date, repetition: Repetition?) {
        scheduled[requestID] = taskID.map { Appearance(taskID: $0, date: date, repetition: repetition) }
    }

    public mutating func retainRequests(_ ids: Set<String>) {
        scheduled = scheduled.filter { ids.contains($0.key) }
    }
}
