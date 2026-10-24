import Foundation

public enum LedgerError: LocalizedError {
    case invalidActivity, invalidCategory, futureSlot, invalidSlot, invalidSchedule, duplicateCategory, reservedCategory, deletedSample, invalidCapture, deletedCapture
    public var errorDescription: String? {
        switch self {
        case .invalidCapture: return "Enter an idea before saving."
        case .deletedCapture: return "This idea was deleted. Restore it before editing."
        case .deletedSample: return "This log was deleted. Use Undo to restore it before editing."
        case .invalidActivity: return "Enter what you were doing (up to 500 characters)."
        case .invalidCategory: return "Choose a category with a name up to 60 characters."
        case .futureSlot: return "A sample can only describe the present or the past."
        case .invalidSlot: return "Choose a valid sample time."
        case .invalidSchedule: return "Choose an available interval and a same-day window of up to 15 hours, in 15-minute steps."
        case .duplicateCategory: return "A category with that name already exists."
        case .reservedCategory: return "Uncategorized is reserved for activities waiting to be grouped. Choose another name."
        }
    }
}

// Lamport revisions make merging phone, Watch, and cloud copies deterministic.
public struct Revision: Codable, Equatable, Comparable, Sendable {
    public var counter: Int64
    public var writer: String
    public init(counter: Int64 = 0, writer: String = "seed") { self.counter = counter; self.writer = writer }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.counter == rhs.counter ? lhs.writer < rhs.writer : lhs.counter < rhs.counter
    }
}

public struct LedgerCategory: Codable, Identifiable, Equatable, Sendable {
    /// Nil in older ledgers. Favorites affect the dashboard, not goal values.
    public var isFavorite: Bool? = nil
    public var parentID: String?
    public var sortOrder: Int?
    public var automaticRole: String?
    public var id: String
    public var name: String
    public var revision: Revision
    public init(id: String = UUID().uuidString, name: String, revision: Revision = Revision(), automaticRole: String? = nil) {
        self.automaticRole = automaticRole
        self.id = id; self.name = name; self.revision = revision
    }
}

/// Kept in backups and sync so an older device cannot resurrect a deleted group.
public struct GroupDeletion: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var automaticRole: String?
    public var revision: Revision
}

public struct LogDeletion: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var deleted: Bool
    public var revision: Revision
}

public struct ReminderTime: Equatable, Sendable {
    public var hour: Int?
    public var minute: Int
    public var id: String { "checkin-\(hour.map(String.init) ?? "hourly")-\(minute)" }
}

// "automatic" is retained for compatibility with older phone/Watch data.
// It now represents an unconfirmed suggestion and never a confirmed group.
public enum CategoryAssignment: String, Codable, Sendable { case automatic, manual }

public struct CheckIn: Codable, Identifiable, Equatable, Sendable {
    public var categorySuggestion: CategorySuggestion?
    /// Present only for a user-confirmed calendar period. Samples remain instantaneous.
    public var intervalStart: Date?
    public var goalID: String?
    /// Credit is fixed when assigned, so moving a goal does not erase past work.
    public var goalShare: Double?
    /// Optional instantaneous self-report: 1 (low) through 5 (high).
    public var mood: Int?
    /// Nil in legacy files. categoryID remains a compatibility mirror of the first selection.
    public var categoryIDs: [String]?
    public var categoryAssignment: CategoryAssignment?
    public var sampleID: String?
    public var id: String { sampleID ?? String(Int64(end.timeIntervalSince1970)) }
    public var end: Date
    public var activity: String
    public var categoryID: String?
    public var revision: Revision
    public init(end: Date, activity: String, categoryID: String?, revision: Revision, sampleID: String? = nil, categoryAssignment: CategoryAssignment? = nil) {
        self.categoryAssignment = categoryAssignment
        self.sampleID = sampleID
        self.end = end; self.activity = activity; self.categoryID = categoryID; self.revision = revision
    }
    public var start: Date { intervalStart ?? end.addingTimeInterval(-900) }
}

public struct Capture: Codable, Identifiable, Equatable, Sendable {
    public var categorySuggestion: CategorySuggestion?
    /// Explicitly clearing labels is also a confirmed choice. Nil supports old files.
    public var categoriesReviewed: Bool?
    /// Shared category IDs; absent in older backups and Watch captures.
    public var categoryIDs: [String]?
    public var deletedAt: Date?
    public var notes: String?
    public var snoozedUntil: Date?
    // Explicit Bring back now bypasses the scheduled 8 a.m. return.
    public var returnedAt: Date?
    public var isReference: Bool?
    // Changes only when starting a fresh review cycle, not when editing notes.
    public var reviewRevision: Revision?
    public var id: String
    public var text: String
    public var createdAt: Date
    public var isDone: Bool
    public var revision: Revision
    public init(id: String = UUID().uuidString, text: String, createdAt: Date = Date(), isDone: Bool = false, revision: Revision) {
        self.id = id; self.text = text; self.createdAt = createdAt; self.isDone = isDone; self.revision = revision
    }
    public func snoozeReturnDate(calendar: Calendar = .current) -> Date? {
        if let returnedAt { return returnedAt }
        return snoozedUntil.flatMap { calendar.date(bySettingHour: 8, minute: 0, second: 0, of: $0) }
    }
    public func rankingArrivalDate(calendar: Calendar = .current) -> Date {
        snoozeReturnDate(calendar: calendar) ?? createdAt
    }
    public func isSnoozed(at now: Date, calendar: Calendar = .current) -> Bool {
        snoozeReturnDate(calendar: calendar).map { $0 > now } ?? false
    }
}

public enum InferenceMethod: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case midpoint, carryForward
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .midpoint: return "Midpoint between samples"
        case .carryForward: return "Previous activity until next sample"
        }
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var reportingTimeZoneIdentifier: String?
    public var notificationsAllDay = false
    public var notificationsEnabled = false
    public var notificationTiming = NotificationTiming.regular
    public var notificationDelivery = NotificationDelivery.automatic
    public var regularNotificationInterval = 15
    public var randomizedNotificationInterval = 15
    public var startMinute = 7 * 60
    public var endMinute = 22 * 60
    public var use24HourTime = false
    public var inferenceMethod = InferenceMethod.midpoint
    public var revision = Revision()
    public init() {}
    private enum CodingKeys: String, CodingKey {
        // Keep the existing wire key so older Watch versions retain the same time zone.
        case reportingTimeZoneIdentifier = "wakingTimeZoneIdentifier"
        case notificationsAllDay, notificationsEnabled, startMinute, endMinute, use24HourTime, inferenceMethod, revision
        case notificationTiming, notificationDelivery, regularNotificationInterval, randomizedNotificationInterval
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        reportingTimeZoneIdentifier = try values.decodeIfPresent(String.self, forKey: .reportingTimeZoneIdentifier)
        notificationsAllDay = try values.decodeIfPresent(Bool.self, forKey: .notificationsAllDay) ?? false
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        notificationTiming = try values.decodeIfPresent(NotificationTiming.self, forKey: .notificationTiming) ?? .regular
        notificationDelivery = try values.decodeIfPresent(NotificationDelivery.self, forKey: .notificationDelivery) ?? .automatic
        regularNotificationInterval = try values.decodeIfPresent(Int.self, forKey: .regularNotificationInterval) ?? 15
        randomizedNotificationInterval = try values.decodeIfPresent(Int.self, forKey: .randomizedNotificationInterval) ?? 15
        startMinute = try values.decodeIfPresent(Int.self, forKey: .startMinute) ?? 420
        endMinute = try values.decodeIfPresent(Int.self, forKey: .endMinute) ?? 1320
        use24HourTime = try values.decodeIfPresent(Bool.self, forKey: .use24HourTime) ?? false
        inferenceMethod = try values.decodeIfPresent(InferenceMethod.self, forKey: .inferenceMethod) ?? .midpoint
        revision = try values.decodeIfPresent(Revision.self, forKey: .revision) ?? Revision()
    }
    public func notificationSchedule() throws -> [ReminderTime] {
        try validateNotificationSettings()
        if notificationsAllDay, 60 % regularNotificationInterval == 0 {
            return stride(from: 0, to: 60, by: regularNotificationInterval).map { ReminderTime(hour: nil, minute: $0) }
        }
        return try notificationMinutes().map { ReminderTime(hour: $0 / 60, minute: $0 % 60) }
    }
    public func notificationMinutes() throws -> [Int] {
        try validateNotificationSettings()
        if notificationsAllDay { return Array(stride(from: 0, to: 1440, by: regularNotificationInterval)) }
        return Array(stride(from: startMinute, through: endMinute, by: regularNotificationInterval))
    }
    public func validateNotificationSettings() throws {
        guard NotificationTiming.intervals.contains(regularNotificationInterval),
              NotificationTiming.intervals.contains(randomizedNotificationInterval) else { throw LedgerError.invalidSchedule }
        if notificationsAllDay { return }
        guard startMinute >= 0, endMinute < 1440, endMinute > startMinute,
              startMinute % 15 == 0, endMinute % 15 == 0,
              endMinute - startMinute <= 900 else { throw LedgerError.invalidSchedule }
    }
}

public struct BreakdownRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var minutes: Double
    public var dayMinutes: Double = 1440
    public var percent: Double { dayMinutes > 0 ? minutes / dayMinutes * 100 : 0 }
}

public struct InferredSegment: Equatable, Sendable {
    public var sampleID: String
    public var start: Date
    public var end: Date
    public var categoryID: String?
    public var minutes: Double { end.timeIntervalSince(start) / 60 }
}

public struct Ledger: Codable, Equatable, Sendable {
    public var datedGoals: [DatedGoal]?
    public var calendarEvents: [CalendarEventRecord]?
    public var weeklyCommitments: [WeeklyCommitment]?
    public var targetBudgets: [TargetBudget]?
    public var reminderImports: [ReminderImportReceipt]?
    public var logDeletions: [LogDeletion]?
    public var groupDeletions: [GroupDeletion]?
    public var inboxRanking: InboxRanking?
    public var schemaVersion = 2
    public var categories: [LedgerCategory] = OfflineGrouping.defaultGroups
    public var entries: [CheckIn] = []
    public var captures: [Capture] = []
    public var settings = Settings()
    public init() {}

    public func nextRevision(writer: String) -> Revision {
        var values = categories.map(\.revision.counter)
        values.append(contentsOf: (datedGoals ?? []).map(\.revision.counter))
        values.append(contentsOf: (calendarEvents ?? []).map(\.revision.counter))
        values.append(contentsOf: (weeklyCommitments ?? []).map(\.revision.counter))
        values.append(contentsOf: (targetBudgets ?? []).map(\.revision.counter))
        values.append(contentsOf: entries.map(\.revision.counter))
        values.append(contentsOf: captures.map(\.revision.counter))
        values.append(contentsOf: (reminderImports ?? []).map(\.revision.counter))
        values.append(contentsOf: (logDeletions ?? []).map(\.revision.counter))
        values.append(contentsOf: (groupDeletions ?? []).map(\.revision.counter))
        values.append(contentsOf: [settings.revision.counter, inboxRanking?.revision.counter ?? 0])
        return Revision(counter: (values.max() ?? 0) + 1, writer: writer)
    }

    public func isLogDeleted(_ id: String) -> Bool { logDeletions?.first { $0.id == id }?.deleted == true }
    public var activeEntries: [CheckIn] {
        let deleted = Set((logDeletions ?? []).filter(\.deleted).map(\.id))
        return entries.filter { !deleted.contains($0.id) }
    }
    public mutating func setLogDeleted(_ id: String, deleted: Bool, writer: String) {
        guard entries.contains(where: { $0.id == id }), isLogDeleted(id) != deleted else { return }
        let record = LogDeletion(id: id, deleted: deleted, revision: nextRevision(writer: writer))
        logDeletions = (logDeletions ?? []).filter { $0.id != id } + [record]
    }

    public static func slotEnd(at date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 900) * 900)
    }

    public static func completedSlots(on day: Date, now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        guard let bounds = calendar.dateInterval(of: .day, for: day) else { return [] }
        var slots: [Date] = []
        var end = bounds.start.addingTimeInterval(900)
        while end <= min(bounds.end, now) { slots.append(end); end = end.addingTimeInterval(900) }
        return slots
    }

    public func entries(on day: Date, calendar: Calendar = .current) -> [CheckIn] {
        guard let bounds = calendar.dateInterval(of: .day, for: day) else { return [] }
        return activeEntries.filter { entry in
            if let start = entry.intervalStart { return start < bounds.end && entry.end > bounds.start }
            return entry.end >= bounds.start && entry.end < bounds.end
        }.sorted {
            $0.end == $1.end ? $0.id < $1.id : $0.end > $1.end
        }
    }

    public func inferredSegments(on day: Date, now: Date = Date(), calendar: Calendar = .current, method: InferenceMethod? = nil) -> [InferredSegment] {
        daySegments(on: day, now: now, calendar: calendar, method: method)
    }

    public func breakdown(on day: Date, now: Date = Date(), calendar: Calendar = .current) -> [BreakdownRow] {
        let allocation = allocation(on: day, now: now, calendar: calendar)
        var rows = children(of: nil).map { category in
            BreakdownRow(id: category.id, name: category.name, minutes: allocation.total(for: category.id, ledger: self), dayMinutes: allocation.trackedMinutes)
        }
        rows.append(BreakdownRow(id: "uncategorized", name: "Uncategorized", minutes: allocation.directMinutes["uncategorized", default: 0], dayMinutes: allocation.trackedMinutes))
        return rows
    }

    public mutating func saveCheckIn(end: Date, activity: String, categoryID: String?, writer: String, now: Date = Date()) throws {
        // Compatibility for a caller editing an old timestamp-based record.
        guard end.timeIntervalSince1970.isFinite else { throw LedgerError.invalidSlot }
        let id = entries.first { $0.end == end }?.id ?? String(Int64(end.timeIntervalSince1970))
        try saveSample(id: id, at: end, activity: activity, categoryID: categoryID, writer: writer, now: now)
    }

    public mutating func saveSample(id: String? = nil, at timestamp: Date, activity: String, categoryID: String?, writer: String, now: Date = Date()) throws {
        try saveSample(id: id, at: timestamp, activity: activity, categoryIDs: categoryID.map { [$0] } ?? [], writer: writer, now: now)
    }

    public mutating func saveCategory(id: String?, name: String, writer: String) throws {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 60 else { throw LedgerError.invalidCategory }
        guard text.caseInsensitiveCompare("Uncategorized") != .orderedSame else { throw LedgerError.reservedCategory }
        guard !categories.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(text) == .orderedSame }) else { throw LedgerError.duplicateCategory }
        let revision = nextRevision(writer: writer)
        if let id {
            guard let index = categories.firstIndex(where: { $0.id == id }) else { throw LedgerError.invalidCategory }
            categories[index].name = text; categories[index].revision = revision
        } else { categories.append(LedgerCategory(name: text, revision: revision)) }
    }

    public mutating func deleteCategory(id: String, writer: String) throws {
        guard let group = categories.first(where: { $0.id == id }) else { throw LedgerError.invalidCategory }
        let deletion = GroupDeletion(id: id, automaticRole: group.automaticRole, revision: nextRevision(writer: writer))
        groupDeletions = (groupDeletions ?? []).filter { $0.id != id } + [deletion]
        categories.removeAll { $0.id == id }
        // Keep raw category references, activity, timestamps and IDs. Deleted shares
        // report as Uncategorized instead of inflating any surviving selection.
        for index in entries.indices where (entries[index].categoryIDs ?? entries[index].categoryID.map { [$0] } ?? []).contains(id) {
            entries[index].categoryIDs = entries[index].categoryIDs ?? entries[index].categoryID.map { [$0] }
            if entries[index].categoryID == id { entries[index].categoryID = nil }
            entries[index].revision = nextRevision(writer: writer)
        }
        for index in categories.indices where categories[index].parentID == id {
            categories[index].parentID = group.parentID
            categories[index].revision = nextRevision(writer: writer)
        }
        try removeIneligibleTargets(writer: writer)
    }

    @discardableResult
    public mutating func addCapture(text: String, id: String = UUID().uuidString, writer: String, now: Date = Date()) throws -> Capture {
        if let saved = captures.first(where: { $0.id == id }) { return saved }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 500 else { throw LedgerError.invalidActivity }
        let capture = Capture(id: id, text: cleaned, createdAt: now, revision: nextRevision(writer: writer))
        captures.append(capture)
        return capture
    }

    public mutating func setCaptureDone(id: String, done: Bool, writer: String) {
        let revision = nextRevision(writer: writer)
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        captures[index].isDone = done; captures[index].revision = revision
        normalizeInboxRanking(writer: writer)
    }

    public mutating func updateCaptureText(id: String, text: String, writer: String) throws {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw LedgerError.invalidCapture }
        guard let index = captures.firstIndex(where: { $0.id == id }), captures[index].deletedAt == nil else { throw LedgerError.deletedCapture }
        guard captures[index].text != cleaned else { return }
        captures[index].text = cleaned
        if captures[index].categorySuggestion != nil { captures[index].categorySuggestion = nil; captures[index].categoryIDs = nil }
        captures[index].revision = nextRevision(writer: writer)
    }

    public mutating func updateCapture(id: String, text: String, notes: String, writer: String) throws {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw LedgerError.invalidCapture }
        guard let index = captures.firstIndex(where: { $0.id == id }), captures[index].deletedAt == nil else { throw LedgerError.deletedCapture }
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedNotes = notes.isEmpty ? nil : notes
        guard captures[index].text != cleaned || captures[index].notes != savedNotes else { return }
        let revision = nextRevision(writer: writer)
        if captures[index].categorySuggestion != nil { captures[index].categorySuggestion = nil; captures[index].categoryIDs = nil }
        captures[index].text = cleaned; captures[index].notes = savedNotes; captures[index].revision = revision
    }

    public mutating func saveSettings(_ value: Settings, writer: String) throws {
        _ = try value.notificationMinutes()
        guard value.reportingTimeZoneIdentifier == nil || TimeZone(identifier: value.reportingTimeZoneIdentifier!) != nil else { throw PlannerError.invalidTimeZone }
        var revised = value; revised.revision = nextRevision(writer: writer); settings = revised
    }

    public mutating func merge(_ other: Ledger) {
        func merged<T: Identifiable>(_ local: [T], _ remote: [T], revision: (T) -> Revision) -> [T] where T.ID == String {
            var result = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { revision($0) < revision($1) ? $1 : $0 })
            for value in remote {
                if let existing = result[value.id], revision(existing) >= revision(value) { continue }
                result[value.id] = value
            }
            return result.values.sorted { $0.id < $1.id }
        }
        categories = merged(categories, other.categories, revision: { $0.revision })
        let goals = merged(datedGoals ?? [], other.datedGoals ?? [], revision: { $0.revision })
        datedGoals = goals.isEmpty ? nil : goals
        let events = merged(calendarEvents ?? [], other.calendarEvents ?? [], revision: { $0.revision })
        calendarEvents = events.isEmpty ? nil : events
        let commitments = merged(weeklyCommitments ?? [], other.weeklyCommitments ?? [], revision: { $0.revision })
        weeklyCommitments = commitments.isEmpty ? nil : commitments
        let budgets = merged(targetBudgets ?? [], other.targetBudgets ?? [], revision: { $0.revision })
        targetBudgets = budgets.isEmpty ? nil : budgets
        let deletions = merged(groupDeletions ?? [], other.groupDeletions ?? [], revision: { $0.revision })
        groupDeletions = deletions.isEmpty ? nil : deletions
        categories.removeAll { group in deletions.contains { $0.id == group.id } }
        entries = merged(entries, other.entries, revision: { $0.revision })
        let removed = merged(logDeletions ?? [], other.logDeletions ?? [], revision: { $0.revision })
        logDeletions = removed.isEmpty ? nil : removed
        // A concurrent sample may still refer to a deleted group. Preserve its
        // observation and revision, and normalize only that obsolete reference.
        for index in entries.indices where deletions.contains(where: { $0.id == entries[index].categoryID }) {
            entries[index].categoryIDs = entries[index].categoryIDs ?? entries[index].categoryID.map { [$0] }
            entries[index].categoryID = nil
        }
        captures = merged(captures, other.captures, revision: { $0.revision })
        let imports = merged(reminderImports ?? [], other.reminderImports ?? [], revision: { $0.revision })
        reminderImports = imports.isEmpty ? nil : imports
        if let ranking = other.inboxRanking, inboxRanking == nil || inboxRanking!.revision < ranking.revision { inboxRanking = ranking }
        if settings.revision < other.settings.revision { settings = other.settings }
    }
}
