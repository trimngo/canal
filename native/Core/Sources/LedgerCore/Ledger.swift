import Foundation

public enum LedgerError: LocalizedError {
    case invalidActivity, invalidCategory, futureSlot, invalidSlot, invalidSchedule, duplicateCategory
    public var errorDescription: String? {
        switch self {
        case .invalidActivity: return "Enter what you were doing (up to 500 characters)."
        case .invalidCategory: return "Choose a category with a name up to 60 characters."
        case .futureSlot: return "Only completed intervals can be logged."
        case .invalidSlot: return "Choose a 15-minute interval."
        case .invalidSchedule: return "Choose a same-day window of up to 15 hours, in 15-minute steps."
        case .duplicateCategory: return "A category with that name already exists."
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

public struct Category: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var revision: Revision
    public init(id: String = UUID().uuidString, name: String, revision: Revision = Revision()) {
        self.id = id; self.name = name; self.revision = revision
    }
}

public struct CheckIn: Codable, Identifiable, Equatable, Sendable {
    public var id: String { String(Int64(end.timeIntervalSince1970)) }
    public var end: Date
    public var activity: String
    public var categoryID: String?
    public var revision: Revision
    public init(end: Date, activity: String, categoryID: String?, revision: Revision) {
        self.end = end; self.activity = activity; self.categoryID = categoryID; self.revision = revision
    }
    public var start: Date { end.addingTimeInterval(-900) }
}

public struct Capture: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var createdAt: Date
    public var isDone: Bool
    public var revision: Revision
    public init(id: String = UUID().uuidString, text: String, createdAt: Date = Date(), isDone: Bool = false, revision: Revision) {
        self.id = id; self.text = text; self.createdAt = createdAt; self.isDone = isDone; self.revision = revision
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var notificationsEnabled = false
    public var startMinute = 7 * 60
    public var endMinute = 22 * 60
    public var use24HourTime = false
    public var revision = Revision()
    public init() {}
    public func notificationMinutes() throws -> [Int] {
        guard startMinute >= 0, endMinute < 1440, endMinute > startMinute,
              startMinute % 15 == 0, endMinute % 15 == 0,
              endMinute - startMinute <= 900 else { throw LedgerError.invalidSchedule }
        return Array(stride(from: startMinute + 15, through: endMinute, by: 15))
    }
}

public struct BreakdownRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var minutes: Int
    public var percent: Double { Double(minutes) / 1440 * 100 }
}

public struct Ledger: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var categories: [Category] = [
        Category(id: "work", name: "Work"), Category(id: "personal", name: "Personal"),
        Category(id: "rest", name: "Rest")
    ]
    public var entries: [CheckIn] = []
    public var captures: [Capture] = []
    public var settings = Settings()
    public init() {}

    public func nextRevision(writer: String) -> Revision {
        let values = categories.map(\.revision.counter) + entries.map(\.revision.counter) + captures.map(\.revision.counter) + [settings.revision.counter]
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
        // The interval ending at midnight belongs to the day it covers.
        return entries.filter { $0.end > bounds.start && $0.end <= bounds.end }.sorted { $0.end > $1.end }
    }

    public func breakdown(on day: Date, calendar: Calendar = .current) -> [BreakdownRow] {
        let logs = entries(on: day, calendar: calendar)
        let known = Set(categories.map(\.id))
        var rows = categories.map { category in
            BreakdownRow(id: category.id, name: category.name, minutes: logs.filter { $0.categoryID == category.id }.count * 15)
        }
        rows.append(BreakdownRow(id: "uncategorized", name: "Uncategorized", minutes: logs.filter { !known.contains($0.categoryID ?? "") }.count * 15))
        rows.append(BreakdownRow(id: "unlogged", name: "Not logged", minutes: max(0, 1440 - logs.count * 15)))
        return rows
    }

    public mutating func saveCheckIn(end: Date, activity: String, categoryID: String?, writer: String, now: Date = Date()) throws {
        let text = activity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else { throw LedgerError.invalidActivity }
        guard abs(end.timeIntervalSince1970.truncatingRemainder(dividingBy: 900)) < 0.001 else { throw LedgerError.invalidSlot }
        guard end <= now else { throw LedgerError.futureSlot }
        if let categoryID, !categories.contains(where: { $0.id == categoryID }) { throw LedgerError.invalidCategory }
        let entry = CheckIn(end: end, activity: text, categoryID: categoryID, revision: nextRevision(writer: writer))
        entries.removeAll { $0.id == entry.id }; entries.append(entry)
    }

    public mutating func saveCategory(id: String?, name: String, writer: String) throws {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 60 else { throw LedgerError.invalidCategory }
        guard !categories.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(text) == .orderedSame }) else { throw LedgerError.duplicateCategory }
        let revision = nextRevision(writer: writer)
        if let id {
            guard let index = categories.firstIndex(where: { $0.id == id }) else { throw LedgerError.invalidCategory }
            categories[index].name = text; categories[index].revision = revision
        } else { categories.append(Category(name: text, revision: revision)) }
    }

    public mutating func addCapture(text: String, writer: String, now: Date = Date()) throws {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 500 else { throw LedgerError.invalidActivity }
        captures.append(Capture(text: cleaned, createdAt: now, revision: nextRevision(writer: writer)))
    }

    public mutating func setCaptureDone(id: String, done: Bool, writer: String) {
        let revision = nextRevision(writer: writer)
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        captures[index].isDone = done; captures[index].revision = revision
    }

    public mutating func saveSettings(_ value: Settings, writer: String) throws {
        _ = try value.notificationMinutes()
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
        entries = merged(entries, other.entries, revision: { $0.revision })
        captures = merged(captures, other.captures, revision: { $0.revision })
        if settings.revision < other.settings.revision { settings = other.settings }
    }
}
