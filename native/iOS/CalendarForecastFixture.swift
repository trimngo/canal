#if DEBUG
import Foundation
import LedgerCore

/// Exercise real forecast math/classification without granting EventKit access
/// or inventing future recorded logs. A fixed reporting zone keeps these cases
/// away from midnight regardless of the CI runner's wall-clock hour.
enum CalendarForecastFixture {
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-calendar-plan") ||
            ProcessInfo.processInfo.arguments.contains("--ui-calendar-plan-source") ||
            ProcessInfo.processInfo.arguments.contains("--ui-calendar-plan-ended")
    }
    static let sourceID = "calendar-plan-fixture"
    static let selectionKey = "ui.calendar-plan.sources"
    static let now = Date()
    static let timeZone: TimeZone = {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let offset = 12 - utc.component(.hour, from: now)
        let name = offset == 0 ? "Etc/GMT" : "Etc/GMT\(offset > 0 ? "-" : "+")\(abs(offset))"
        return TimeZone(identifier: name)!
    }()
    static var snapshots: [CalendarEventSnapshot] {
        [("rehearsal", "Rehearsal", -1800.0, 1800.0),
         ("class", "Class preparation", 3600.0, 7200.0),
         ("unknown", "Not categorized yet", 10800.0, 12600.0)].map { value in
            let (id, title, start, end) = value
            let ended = id == "class" && ProcessInfo.processInfo.arguments.contains("--ui-calendar-plan-ended")
            return CalendarEventSnapshot(id: id, calendarID: sourceID, calendarName: "Today plan", title: title,
                                  start: now.addingTimeInterval(ended ? -7200 : start), end: now.addingTimeInterval(ended ? -3600 : end))
        }
    }
    static func ledger() throws -> Ledger {
        var ledger = Ledger()
        ledger.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "music", name: "Music"),
                             LedgerCategory(id: "guitar", name: "Guitar")]
        try ledger.moveCategory("guitar", to: "music", writer: "fixture")
        ledger.settings.reportingTimeZoneIdentifier = timeZone.identifier
        ledger.settings.categoryMatching = .broader
        ledger.settings.categoryMatchRules = [.init(phrase: "Class", categoryID: "work"), .init(phrase: "Rehearsal", categoryID: "guitar")]
        let recorded = CalendarEventSnapshot(id: "recorded", calendarID: sourceID, calendarName: "Today plan", title: "Completed morning work",
            start: now.addingTimeInterval(-10800), end: now.addingTimeInterval(-7200))
        ledger.collectCalendarEvents([recorded], writer: "fixture", now: now)
        try ledger.decideCalendarEvent(recorded.id, confirm: true, categoryIDs: ["work"], writer: "fixture", now: now)
        return ledger
    }
}
#endif
