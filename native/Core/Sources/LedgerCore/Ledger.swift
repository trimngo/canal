import Foundation

public enum LedgerError: LocalizedError {
    case invalidActivity, invalidCategory, futureSlot, invalidSlot, invalidSchedule, duplicateCategory, reservedCategory
    public var errorDescription: String? {
        switch self {
        case .invalidActivity: return "Enter what you were doing (up to 500 characters)."
        case .invalidCategory: return "Choose a category with a name up to 60 characters."
        case .futureSlot: return "A sample can only describe the present or the past."
        case .invalidSlot: return "Choose a valid sample time."
        case .invalidSchedule: return "Choose a same-day window of up to 15 hours, in 15-minute steps."
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

// "automatic" is retained for compatibility with older phone/Watch data.
// It now represents an unconfirmed suggestion and never a confirmed group.
public enum CategoryAssignment: String, Codable, Sendable { case automatic, manual }

public struct CheckIn: Codable, Identifiable, Equatable, Sendable {
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
    public var start: Date { end.addingTimeInterval(-900) }
}

public struct Capture: Codable, Identifiable, Equatable, Sendable {
    public var deletedAt: Date?
    public var id: String
    public var text: String
    public var createdAt: Date
    public var isDone: Bool
    public var revision: Revision
    public init(id: String = UUID().uuidString, text: String, createdAt: Date = Date(), isDone: Bool = false, revision: Revision) {
        self.id = id; self.text = text; self.createdAt = createdAt; self.isDone = isDone; self.revision = revision
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
    public var showRemainingTime = false
    public var bedtimeMinute = 22 * 60
    public var notificationsEnabled = false
    public var startMinute = 7 * 60
    public var endMinute = 22 * 60
    public var use24HourTime = false
    public var inferenceMethod = InferenceMethod.midpoint
    public var revision = Revision()
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case notificationsEnabled, startMinute, endMinute, use24HourTime, inferenceMethod, revision, showRemainingTime, bedtimeMinute
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        startMinute = try values.decodeIfPresent(Int.self, forKey: .startMinute) ?? 420
        endMinute = try values.decodeIfPresent(Int.self, forKey: .endMinute) ?? 1320
        use24HourTime = try values.decodeIfPresent(Bool.self, forKey: .use24HourTime) ?? false
        inferenceMethod = try values.decodeIfPresent(InferenceMethod.self, forKey: .inferenceMethod) ?? .midpoint
        revision = try values.decodeIfPresent(Revision.self, forKey: .revision) ?? Revision()
        showRemainingTime = try values.decodeIfPresent(Bool.self, forKey: .showRemainingTime) ?? false
        bedtimeMinute = try values.decodeIfPresent(Int.self, forKey: .bedtimeMinute) ?? 1320
    }
    public func notificationMinutes() throws -> [Int] {
        guard startMinute >= 0, endMinute < 1440, endMinute > startMinute,
              startMinute % 15 == 0, endMinute % 15 == 0,
              endMinute - startMinute <= 900 else { throw LedgerError.invalidSchedule }
        return Array(stride(from: startMinute, through: endMinute, by: 15))
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
        values.append(contentsOf: entries.map(\.revision.counter))
        values.append(contentsOf: captures.map(\.revision.counter))
        values.append(contentsOf: (groupDeletions ?? []).map(\.revision.counter))
        values.append(contentsOf: [settings.revision.counter, inboxRanking?.revision.counter ?? 0])
        return Revision(counter: (values.max() ?? 0) + 1, writer: writer)
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
        return entries.filter { $0.end >= bounds.start && $0.end < bounds.end }.sorted {
            $0.end == $1.end ? $0.id < $1.id : $0.end > $1.end
        }
    }

    public func inferredSegments(on day: Date, now: Date = Date(), calendar: Calendar = .current, method: InferenceMethod? = nil) -> [InferredSegment] {
        guard let bounds = calendar.dateInterval(of: .day, for: day), now > bounds.start else { return [] }
        let eligible = entries(on: day, calendar: calendar).filter { $0.end <= min(bounds.end, now) }
        // Closed days end at the last observation, rather than assuming the
        // final activity continued while the person slept.
        let cutoff = now >= bounds.end ? (eligible.first?.end ?? bounds.start) : now
        // Keep all raw observations. If timestamps coincide, infer from the latest
        // revision once, so contradictory observations cannot double-count time.
        let distinct = Dictionary(eligible.map { ($0.end, $0) }, uniquingKeysWith: {
            if $0.revision == $1.revision { return $0.id < $1.id ? $1 : $0 }
            return $0.revision < $1.revision ? $1 : $0
        }).values.sorted { $0.end < $1.end }
        let rule = method ?? settings.inferenceMethod
        func midpoint(_ a: Date, _ b: Date) -> Date { a.addingTimeInterval(b.timeIntervalSince(a) / 2) }
        return distinct.indices.compactMap { index in
            let sample = distinct[index]
            let start: Date
            if index == 0 || rule == .carryForward { start = sample.end }
            else { start = midpoint(distinct[index - 1].end, sample.end) }
            let end: Date
            if index == distinct.count - 1 { end = cutoff }
            else if rule == .carryForward { end = distinct[index + 1].end }
            else { end = midpoint(sample.end, distinct[index + 1].end) }
            guard end > start else { return nil }
            return InferredSegment(sampleID: sample.id, start: start, end: end, categoryID: confirmedCategoryID(for: sample))
        }
    }

    public func breakdown(on day: Date, now: Date = Date(), calendar: Calendar = .current) -> [BreakdownRow] {
        let segments = inferredSegments(on: day, now: now, calendar: calendar)
        let dayMinutes = segments.reduce(0) { $0 + $1.minutes }
        let known = Set(categories.map(\.id))
        var rows = categories.map { category in
            BreakdownRow(id: category.id, name: category.name, minutes: segments.filter { $0.categoryID == category.id }.reduce(0) { $0 + $1.minutes }, dayMinutes: dayMinutes)
        }
        rows.append(BreakdownRow(id: "uncategorized", name: "Uncategorized", minutes: segments.filter { !known.contains($0.categoryID ?? "") }.reduce(0) { $0 + $1.minutes }, dayMinutes: dayMinutes))
        return rows
    }

    public mutating func saveCheckIn(end: Date, activity: String, categoryID: String?, writer: String, now: Date = Date()) throws {
        // Compatibility for a caller editing an old timestamp-based record.
        guard end.timeIntervalSince1970.isFinite else { throw LedgerError.invalidSlot }
        let id = entries.first { $0.end == end }?.id ?? String(Int64(end.timeIntervalSince1970))
        try saveSample(id: id, at: end, activity: activity, categoryID: categoryID, writer: writer, now: now)
    }

    public mutating func saveSample(id: String? = nil, at timestamp: Date, activity: String, categoryID: String?, writer: String, now: Date = Date()) throws {
        let text = activity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else { throw LedgerError.invalidActivity }
        guard timestamp.timeIntervalSince1970.isFinite else { throw LedgerError.invalidSlot }
        guard timestamp <= now else { throw LedgerError.futureSlot }
        if let categoryID, !categories.contains(where: { $0.id == categoryID }) { throw LedgerError.invalidCategory }
        let revision = nextRevision(writer: writer)
        let sampleID = id ?? UUID().uuidString
        entries.removeAll { $0.id == sampleID }
        let assignment: CategoryAssignment = categoryID == nil ? .automatic : .manual
        let entry = CheckIn(end: timestamp, activity: text, categoryID: categoryID, revision: revision, sampleID: sampleID, categoryAssignment: assignment)
        entries.append(entry)
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
        for index in entries.indices where entries[index].categoryID == id {
            let revision = nextRevision(writer: writer)
            entries[index].categoryID = nil
            entries[index].categoryAssignment = .automatic
            entries[index].revision = revision
        }
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
    }

    public mutating func saveSettings(_ value: Settings, writer: String) throws {
        _ = try value.notificationMinutes()
        guard (0..<1440).contains(value.bedtimeMinute) else { throw LedgerError.invalidSchedule }
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
        let deletions = merged(groupDeletions ?? [], other.groupDeletions ?? [], revision: { $0.revision })
        groupDeletions = deletions.isEmpty ? nil : deletions
        categories.removeAll { group in deletions.contains { $0.id == group.id } }
        entries = merged(entries, other.entries, revision: { $0.revision })
        // A concurrent sample may still refer to a deleted group. Preserve its
        // observation and revision, and normalize only that obsolete reference.
        for index in entries.indices where deletions.contains(where: { $0.id == entries[index].categoryID }) {
            entries[index].categoryID = nil; entries[index].categoryAssignment = .automatic
        }
        captures = merged(captures, other.captures, revision: { $0.revision })
        if let ranking = other.inboxRanking, inboxRanking == nil || inboxRanking!.revision < ranking.revision { inboxRanking = ranking }
        if settings.revision < other.settings.revision { settings = other.settings }
    }
}
