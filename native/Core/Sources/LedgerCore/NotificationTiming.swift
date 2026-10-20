import Foundation

public enum NotificationTiming: String, Codable, CaseIterable, Identifiable, Sendable {
    case regular, randomized
    public var id: String { rawValue }
    public var name: String { self == .regular ? "Regular" : "Randomized" }
    public static let intervals = [5, 10, 15, 20, 30, 45, 60, 90, 120]
}

extension Settings {
    /// A finite queue is needed for fresh random times, or a frequent window
    /// whose repeating requests would exceed Apple's pending-notification limit.
    public var usesQueuedNotifications: Bool {
        notificationTiming == .randomized || ((try? notificationSchedule().count) ?? 0) > 63
    }

    /// Preserve already scheduled prompts when refilling: an unrelated log save
    /// must not move the next notification farther into the future.
    public func notificationQueue(existing: [Date], now: Date, capacity: Int = 60,
                                  calendar: Calendar = .current,
                                  random: () -> Double = { Double.random(in: 0...1) }) throws -> [Date] {
        try validateNotificationSettings()
        guard capacity > 0 else { return [] }
        var dates = Array(Set(existing.filter { $0 > now })).sorted().prefix(capacity).map { $0 }
        dates += try notificationDates(after: dates.last ?? now, count: capacity - dates.count, calendar: calendar, random: random)
        return dates
    }

    public func notificationDates(after date: Date, count: Int, calendar: Calendar = .current,
                                  random: () -> Double = { Double.random(in: 0...1) }) throws -> [Date] {
        try validateNotificationSettings()
        guard count > 0 else { return [] }
        if notificationTiming == .regular {
            let minutes = try notificationMinutes()
            var day = calendar.startOfDay(for: date), result: [Date] = []
            while result.count < count {
                // Calendar arithmetic keeps local hours consistent across DST.
                let times = Set(minutes.compactMap {
                    calendar.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0,
                                  of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
                }).sorted()
                for time in times where time > date && calendar.isDate(time, inSameDayAs: day) {
                    result.append(time)
                    if result.count == count { return result }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return result
        }
        var cursor = date, result: [Date] = []
        while result.count < count {
            // Uniform bounded jitter: e.g. 10–20 minutes for a 15-minute mean.
            let draw = random()
            let unit = draw.isFinite ? min(1, max(0, draw)) : 0.5
            let gap = Double(randomizedNotificationInterval * 60) * (2.0 / 3.0 + unit * 2.0 / 3.0)
            if notificationsAllDay {
                cursor = cursor.addingTimeInterval(gap)
            } else {
                var day = calendar.startOfDay(for: cursor)
                while true {
                    let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: day)!
                    let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0, of: day)!
                    // A spring-forward transition can remove the entire window.
                    if end <= start {
                        day = calendar.date(byAdding: .day, value: 1, to: day)!
                        continue
                    }
                    let candidate = max(cursor, start).addingTimeInterval(gap)
                    if candidate <= end { cursor = candidate; break }
                    // Skip quiet hours. A window shorter than a random gap still
                    // gets one sample at a random point inside the window.
                    if cursor <= start, gap > end.timeIntervalSince(start) {
                        cursor = start.addingTimeInterval(max(1, end.timeIntervalSince(start) * (0.1 + unit * 0.9)))
                        break
                    }
                    day = calendar.date(byAdding: .day, value: 1, to: day)!
                }
            }
            result.append(cursor)
        }
        return result
    }
}
