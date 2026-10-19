import Foundation

/// Snoozes return at the start of a local date, across daylight-saving changes.
/// Weekdays mean Monday–Friday, independent of the calendar's first weekday.
public enum InboxSnooze {
    public static func after(days: Int, from date: Date, calendar: Calendar = .current) -> Date? {
        guard days > 0 else { return nil }
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date))
    }

    public static func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        [1, 7].contains(calendar.component(.weekday, from: date))
    }

    public static func weekdayOnOrAfter(_ date: Date, calendar: Calendar = .current) -> Date {
        let date = calendar.startOfDay(for: date)
        switch calendar.component(.weekday, from: date) {
        case 7: return calendar.date(byAdding: .day, value: 2, to: date) ?? date
        case 1: return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        default: return date
        }
    }

    public static func nextWeekday(after date: Date, calendar: Calendar = .current) -> Date? {
        guard let tomorrow = after(days: 1, from: date, calendar: calendar) else { return nil }
        return weekdayOnOrAfter(tomorrow, calendar: calendar)
    }
}
