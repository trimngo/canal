import Foundation

public enum DatedGoalError: LocalizedError {
    case invalidGoal, missingGoal
    public var errorDescription: String? {
        switch self {
        case .invalidGoal: return "Enter a name, positive hours, and a deadline after the start date."
        case .missingGoal: return "This goal is no longer available."
        }
    }
}

/// Separate from percentage targets. A tombstone retains historical assignments.
public struct DatedGoal: Codable, Identifiable, Equatable, Sendable {
    /// A migrated tombstone must never manufacture a deleted task when cloud
    /// records arrive before the corresponding Capture.
    public var migratedToTask: Bool? = nil
    public var id: String
    public var name: String
    public var categoryID: String?
    public var targetMinutes: Double
    public var startDate: Date
    public var deadline: Date
    /// Freeze the planning window and zone so changes to notification settings
    /// do not move an existing goal's original pace line.
    public var dayStartMinute: Int
    public var dayEndMinute: Int
    public var timeZoneIdentifier: String
    public var deleted: Bool
    public var revision: Revision
}

public struct DatedGoalProgress: Identifiable, Equatable, Sendable {
    public var goal: DatedGoal
    public var actualMinutes: Double
    public var expectedMinutes: Double
    public var remainingWorkdays: Double
    public var id: String { goal.id }
    public var remainingMinutes: Double { max(0, goal.targetMinutes - actualMinutes) }
    public var differenceMinutes: Double { actualMinutes - expectedMinutes }
    public var fraction: Double { min(1, max(0, actualMinutes / goal.targetMinutes)) }
    public var dailyMinutesNeeded: Double? { remainingWorkdays > 0 ? remainingMinutes / remainingWorkdays : nil }
    public var isMet: Bool { remainingMinutes < 0.01 }
}

extension Ledger {
    public var activeDatedGoals: [DatedGoal] {
        (datedGoals ?? []).filter { !$0.deleted }.sorted {
            if $0.deadline != $1.deadline { return $0.deadline < $1.deadline }
            return $0.id < $1.id
        }
    }

    @discardableResult
    public mutating func saveDatedGoal(id: String? = nil, name: String, categoryID: String?, targetMinutes: Double,
                                      startDate: Date, deadline: Date, writer: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120, targetMinutes.isFinite, targetMinutes > 0,
              startDate.timeIntervalSince1970.isFinite, deadline.timeIntervalSince1970.isFinite, deadline > startDate else { throw DatedGoalError.invalidGoal }
        if let categoryID, !categories.contains(where: { $0.id == categoryID }) { throw LedgerError.invalidCategory }
        if let id, !(datedGoals ?? []).contains(where: { $0.id == id && !$0.deleted }) { throw DatedGoalError.missingGoal }
        let previous = (datedGoals ?? []).first { $0.id == id }
        let goal = DatedGoal(id: id ?? UUID().uuidString, name: name, categoryID: categoryID, targetMinutes: targetMinutes,
            startDate: startDate, deadline: deadline,
            dayStartMinute: previous?.dayStartMinute ?? settings.startMinute,
            dayEndMinute: previous?.dayEndMinute ?? settings.endMinute,
            timeZoneIdentifier: previous?.timeZoneIdentifier ?? reportingCalendar().timeZone.identifier,
            deleted: false, revision: nextRevision(writer: writer))
        datedGoals = (datedGoals ?? []).filter { $0.id != goal.id } + [goal]
        return goal.id
    }

    public mutating func deleteDatedGoal(_ id: String, writer: String) {
        guard let index = datedGoals?.firstIndex(where: { $0.id == id && !$0.deleted }) else { return }
        let revision = nextRevision(writer: writer)
        datedGoals?[index].deleted = true; datedGoals?[index].revision = revision
    }

    public mutating func assignGoal(_ goalID: String?, to entryID: String, writer: String) throws {
        guard let index = entries.firstIndex(where: { $0.id == entryID }), !isLogDeleted(entryID) else { throw LedgerError.deletedSample }
        if goalID != nil, entries[index].goalID == goalID, entries[index].goalShare != nil { return }
        if let goalID {
            guard let goal = activeDatedGoals.first(where: { $0.id == goalID }) else {
                // Keep historical links editable after deletion or while a
                // newer log arrives before its goal through device sync.
                if entries[index].goalID == goalID { return }
                throw DatedGoalError.missingGoal
            }
            if let category = goal.categoryID, categories.contains(where: { $0.id == category }) {
                let family = Set([category] + descendants(of: category).map(\.id))
                var ids = confirmedCategoryIDs(for: entries[index])
                if Set(ids).isDisjoint(with: family) {
                    let conflicts = Set(categoryConflicts(category, with: ids))
                    ids.removeAll { conflicts.contains($0) }; ids.append(category)
                    try confirmCategories(for: entryID, categoryIDs: ids, writer: writer)
                }
            }
        }
        let share = datedGoalShare(for: entries[index], goalID: goalID)
        guard entries[index].goalID != goalID || entries[index].goalShare != share else { return }
        let revision = nextRevision(writer: writer)
        entries[index].goalID = goalID; entries[index].goalShare = share; entries[index].revision = revision
    }

    func datedGoalShare(for entry: CheckIn, goalID: String?) -> Double? {
        if let share = taskShare(for: entry, taskID: goalID) { return share }
        guard let goalID, let goal = (datedGoals ?? []).first(where: { $0.id == goalID }) else { return nil }
        guard let category = goal.categoryID, categories.contains(where: { $0.id == category }) else { return 1 }
        let family = Set([category] + descendants(of: category).map(\.id))
        let ids = allocationCategoryIDs(for: entry)
        return ids.isEmpty ? 0 : Double(ids.filter { family.contains($0) }.count) / Double(ids.count)
    }

    /// Each included Monday–Friday counts as one planned workday. The baseline
    /// advances within that day's portion before the deadline. Daily catch-up
    /// uses the count of remaining dates, including today if time remains.
    /// Logged work outside these planning windows still counts in full.
    public static func workdayUnits(from start: Date, to end: Date, goal: DatedGoal, countDays: Bool = false) -> Double {
        guard end > start else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: goal.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        let firstMinute = (0..<1440).contains(goal.dayStartMinute) ? goal.dayStartMinute : 420
        let lastMinute = goal.dayEndMinute > firstMinute && goal.dayEndMinute < 1440 ? goal.dayEndMinute : 1320
        var day = cal.startOfDay(for: start), result = 0.0
        while day < end {
            let weekday = cal.component(.weekday, from: day)
            if (2...6).contains(weekday),
               let a = cal.date(bySettingHour: firstMinute / 60, minute: firstMinute % 60, second: 0, of: day),
               let b = cal.date(bySettingHour: lastMinute / 60, minute: lastMinute % 60, second: 0, of: day), b > a {
                let plannedStart = max(a, goal.startDate), plannedEnd = min(b, goal.deadline)
                let overlap = min(end, plannedEnd).timeIntervalSince(max(start, plannedStart))
                if plannedEnd > plannedStart, overlap > 0 { result += countDays ? 1 : overlap / plannedEnd.timeIntervalSince(plannedStart) }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return result
    }

    public func datedGoalProgress(now: Date = Date(), calendar: Calendar = .current) -> [DatedGoalProgress] {
        let goals = activeDatedGoals
        guard let first = goals.map(\.startDate).min(), first < now else {
            return goals.map { progress(for: $0, minutes: 0, now: now) }
        }
        let cal = reportingCalendar(calendar)
        let byID = Dictionary(activeEntries.map { ($0.id, $0) }, uniquingKeysWith: { $0.revision < $1.revision ? $1 : $0 })
        let goalByID = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })
        var totals: [String: Double] = [:]
        // Only dates with relevant observations/periods need estimation.
        let days = activityDays(from: first, through: now, calendar: cal)
        for day in days {
            for segment in inferredSegments(on: day, now: now, calendar: cal) {
                guard let entry = byID[segment.sampleID], let id = entry.goalID, let goal = goalByID[id] else { continue }
                let minutes = max(0, min(now, segment.end).timeIntervalSince(max(goal.startDate, segment.start))) / 60
                var share = entry.goalShare ?? 1.0
                if entry.goalShare == nil, let category = goal.categoryID, categories.contains(where: { $0.id == category }) {
                    let ids = allocationCategoryIDs(for: entry)
                    let family = Set([category] + descendants(of: category).map(\.id))
                    share = ids.isEmpty ? 0 : Double(ids.filter { family.contains($0) }.count) / Double(ids.count)
                }
                totals[id, default: 0] += minutes * share
            }
        }
        return goals.map { progress(for: $0, minutes: totals[$0.id, default: 0], now: now) }
    }
    func progress(for goal: DatedGoal, minutes: Double, now: Date) -> DatedGoalProgress {
        let total = Self.workdayUnits(from: goal.startDate, to: goal.deadline, goal: goal)
        let elapsed = Self.workdayUnits(from: goal.startDate, to: min(now, goal.deadline), goal: goal)
        // A weekend-only goal uses elapsed clock time for its baseline; it is
        // explicitly shown without remaining workdays rather than dividing by zero.
        let fraction = now >= goal.deadline ? 1 : now <= goal.startDate ? 0 : total > 0 ? elapsed / total : max(0, min(1, now.timeIntervalSince(goal.startDate) / goal.deadline.timeIntervalSince(goal.startDate)))
        return DatedGoalProgress(goal: goal, actualMinutes: minutes, expectedMinutes: goal.targetMinutes * fraction,
            remainingWorkdays: Self.workdayUnits(from: max(now, goal.startDate), to: goal.deadline, goal: goal, countDays: true))
    }
}
