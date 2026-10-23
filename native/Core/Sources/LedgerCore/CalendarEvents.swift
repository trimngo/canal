import Foundation

public struct CalendarEventSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var calendarID: String
    public var calendarName: String
    public var title: String
    public var start: Date
    public var end: Date
    public init(id: String, calendarID: String, calendarName: String, title: String, start: Date, end: Date) {
        self.id = id; self.calendarID = calendarID; self.calendarName = calendarName
        self.title = title; self.start = start; self.end = end
    }
}
public enum CalendarEventDecision: String, Codable, Sendable { case pending, confirmed, skipped }
public struct CalendarEventRecord: Codable, Identifiable, Equatable, Sendable {
    public var snapshot: CalendarEventSnapshot
    public var decision: CalendarEventDecision
    public var revision: Revision
    public var id: String { snapshot.id }
    public var logID: String { "calendar-" + id }
}
public enum CalendarImportError: LocalizedError {
    case invalidEvent
    public var errorDescription: String? { "Choose a calendar event that has ended and has a valid start and end time." }
}

extension Ledger {
    public mutating func collectCalendarEvents(_ snapshots: [CalendarEventSnapshot], writer: String, now: Date = Date()) {
        for snapshot in snapshots where snapshot.start.timeIntervalSince1970.isFinite && snapshot.end.timeIntervalSince1970.isFinite && snapshot.end > snapshot.start && snapshot.end <= now {
            if let existing = calendarEvents?.first(where: { $0.id == snapshot.id }), existing.decision != .pending || existing.snapshot == snapshot { continue }
            let record = CalendarEventRecord(snapshot: snapshot, decision: .pending, revision: nextRevision(writer: writer))
            calendarEvents = (calendarEvents ?? []).filter { $0.id != record.id } + [record]
        }
    }
    public mutating func decideCalendarEvent(_ id: String, confirm: Bool, categoryIDs: [String] = [], goalID: String? = nil,
                                             writer: String, now: Date = Date()) throws {
        guard let index = calendarEvents?.firstIndex(where: { $0.id == id }), let record = calendarEvents?[index] else { throw CalendarImportError.invalidEvent }
        let event = record.snapshot
        guard event.end > event.start, event.end <= now else { throw CalendarImportError.invalidEvent }
        var draft = self
        if confirm {
            if record.decision == .confirmed { return } // Idempotent repeated callbacks.
            try draft.saveSample(id: record.logID, at: event.end, activity: String(event.title.prefix(500)), categoryIDs: categoryIDs, writer: writer, now: now)
            if let entry = draft.entries.firstIndex(where: { $0.id == record.logID }) { draft.entries[entry].intervalStart = event.start }
            try draft.assignGoal(goalID, to: record.logID, writer: writer)
        } else if record.decision == .confirmed {
            draft.setLogDeleted(record.logID, deleted: true, writer: writer)
        }
        let revision = draft.nextRevision(writer: writer)
        draft.calendarEvents?[index].decision = confirm ? .confirmed : .skipped
        draft.calendarEvents?[index].revision = revision
        self = draft
    }

    /// Confirmed periods own their slots. More recently edited periods win when
    /// two confirmed events overlap; every original record remains stored.
    func daySegments(on day: Date, now: Date, calendar: Calendar, method: InferenceMethod?) -> [InferredSegment] {
        guard let bounds = dayBounds(on: day, calendar: calendar), now > bounds.start else { return [] }
        let cutoff = min(bounds.end, now)
        let explicit = activeEntries.filter { entry in
            guard let start = entry.intervalStart else { return false }
            return entry.end > start && entry.end > bounds.start && start < cutoff && entry.end <= now
        }.sorted { $0.revision == $1.revision ? $0.id > $1.id : $0.revision > $1.revision }
        var result: [InferredSegment] = [], occupied: [DateInterval] = []
        func pieces(_ start: Date, _ end: Date) -> [DateInterval] {
            guard end > start else { return [] }
            var values = [DateInterval(start: start, end: end)]
            for block in occupied {
                values = values.flatMap { value -> [DateInterval] in
                    guard block.start < value.end && block.end > value.start else { return [value] }
                    var kept: [DateInterval] = []
                    if value.start < block.start { kept.append(DateInterval(start: value.start, end: block.start)) }
                    if value.end > block.end { kept.append(DateInterval(start: block.end, end: value.end)) }
                    return kept
                }
            }
            return values
        }
        for entry in explicit {
            let start = max(bounds.start, entry.intervalStart!), end = min(cutoff, entry.end)
            for piece in pieces(start, end) {
                result.append(InferredSegment(sampleID: entry.id, start: piece.start, end: piece.end, categoryID: confirmedCategoryID(for: entry)))
            }
            occupied.append(DateInterval(start: start, end: end))
        }
        for segment in estimatedSampleSegments(on: day, now: now, calendar: calendar, method: method) {
            for piece in pieces(segment.start, segment.end) {
                result.append(InferredSegment(sampleID: segment.sampleID, start: piece.start, end: piece.end, categoryID: segment.categoryID))
            }
        }
        return result.sorted { $0.start == $1.start ? $0.sampleID < $1.sampleID : $0.start < $1.start }
    }

    public func activityDays(from start: Date, through end: Date, calendar: Calendar = .current) -> [Date] {
        guard end >= start else { return [] }
        let cal = reportingCalendar(calendar)
        var days = Set<Date>()
        for entry in activeEntries where entry.end <= end {
            guard let intervalStart = entry.intervalStart else {
                if entry.end >= start { days.insert(cal.startOfDay(for: entry.end)) }; continue
            }
            guard entry.end > start else { continue }
            var day = cal.startOfDay(for: max(start, intervalStart))
            while day < min(end, entry.end) {
                days.insert(day)
                guard let next = cal.date(byAdding: .day, value: 1, to: day), next > day else { break }; day = next
            }
        }
        return days.sorted()
    }
}
