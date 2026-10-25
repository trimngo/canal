import Foundation

public enum TaskPlanError: LocalizedError {
    case invalidEstimate, invalidStart
    public var errorDescription: String? {
        switch self {
        case .invalidEstimate: return "Enter a positive number of work hours, or leave the estimate blank."
        case .invalidStart: return "Choose a valid start date."
        }
    }
}

/// Optional work estimate on an ordinary Inbox item. Due dates use CaptureTiming.
/// The planning window is frozen at entry; it never filters activity observations.
public struct CaptureWorkPlan: Codable, Equatable, Sendable {
    public var estimatedMinutes: Double?
    public var startDate: Date?
    public var dayStartMinute: Int
    public var dayEndMinute: Int
    public var timeZoneIdentifier: String
}

extension Ledger {
    public func isFocusTask(_ task: Capture, now: Date = Date()) -> Bool {
        guard task.deletedAt == nil, !task.isDone, task.isReference != true, !task.isSnoozed(at: now),
              let plan = task.workPlan, let estimate = plan.estimatedMinutes, estimate.isFinite, estimate > 0,
              task.timing?.kind == .dueDate, let due = task.timing?.dueAt else { return false }
        return due.timeIntervalSince1970.isFinite
    }

    public func focusTasks(now: Date = Date()) -> [Capture] {
        captures.filter { isFocusTask($0, now: now) }.sorted {
            if $0.timing?.dueAt != $1.timing?.dueAt { return $0.timing!.dueAt! < $1.timing!.dueAt! }
            return $0.id < $1.id
        }
    }

    public mutating func setTaskPlan(_ id: String, estimatedMinutes: Double?, startDate: Date?, writer: String) throws {
        guard let index = captures.firstIndex(where: { $0.id == id }), captures[index].deletedAt == nil else { throw LedgerError.deletedCapture }
        if let minutes = estimatedMinutes {
            guard minutes.isFinite, minutes > 0 else { throw TaskPlanError.invalidEstimate }
        }
        if let startDate, !startDate.timeIntervalSince1970.isFinite { throw TaskPlanError.invalidStart }
        let old = captures[index].workPlan
        let value: CaptureWorkPlan? = estimatedMinutes != nil || startDate != nil ?
            CaptureWorkPlan(estimatedMinutes: estimatedMinutes, startDate: startDate,
                dayStartMinute: old?.dayStartMinute ?? settings.startMinute,
                dayEndMinute: old?.dayEndMinute ?? settings.endMinute,
                timeZoneIdentifier: old?.timeZoneIdentifier ?? reportingCalendar().timeZone.identifier) : nil
        guard old != value else { return }
        let revision = nextRevision(writer: writer)
        captures[index].workPlan = value; captures[index].revision = revision
    }

    /// Convert once, retaining IDs so every historical log link stays intact.
    /// Legacy goal records remain as sync tombstones, never as a second task.
    public mutating func migrateGoalsToTasks(writer: String) {
        for goal in datedGoals ?? [] {
            if goal.migratedToTask == true { continue }
            if !captures.contains(where: { $0.id == goal.id }) {
                if goal.deleted && !entries.contains(where: { $0.goalID == goal.id }) { continue }
                var task = Capture(id: goal.id, text: goal.name, createdAt: goal.startDate, revision: nextRevision(writer: writer))
                task.timing = .due(goal.deadline)
                task.workPlan = CaptureWorkPlan(estimatedMinutes: goal.targetMinutes, startDate: goal.startDate,
                    dayStartMinute: goal.dayStartMinute, dayEndMinute: goal.dayEndMinute, timeZoneIdentifier: goal.timeZoneIdentifier)
                task.categoryIDs = goal.categoryID.map { [$0] }; task.categoriesReviewed = goal.categoryID != nil
                if goal.deleted { task.deletedAt = goal.startDate }
                captures.append(task)
            }
            if let index = datedGoals?.firstIndex(where: { $0.id == goal.id }) {
                let revision = nextRevision(writer: writer)
                datedGoals?[index].deleted = true; datedGoals?[index].migratedToTask = true; datedGoals?[index].revision = revision
            }
        }
    }

    public mutating func assignTask(_ taskID: String?, to entryID: String, writer: String) throws {
        guard let index = entries.firstIndex(where: { $0.id == entryID }), !isLogDeleted(entryID) else { throw LedgerError.deletedSample }
        // Reviewing an existing link must not apply a task's newer categories
        // retroactively. Explicit log-category edits already recalculate credit.
        if taskID != nil, entries[index].goalID == taskID, entries[index].goalShare != nil { return }
        if let taskID {
            guard let task = captures.first(where: { $0.id == taskID }) else {
                if entries[index].goalID == taskID { return }
                throw LedgerError.invalidCapture
            }
            // Deleted tasks keep their historical links but cannot receive new work.
            if task.deletedAt != nil, entries[index].goalID != taskID { throw LedgerError.deletedCapture }
            var ids = confirmedCategoryIDs(for: entries[index])
            for category in categoryIDs(for: task) {
                let family = Set([category] + descendants(of: category).map(\.id))
                if Set(ids).isDisjoint(with: family) {
                    let conflicts = Set(categoryConflicts(category, with: ids))
                    ids.removeAll { conflicts.contains($0) }; ids.append(category)
                }
            }
            if Set(ids) != Set(confirmedCategoryIDs(for: entries[index])) {
                try confirmCategories(for: entryID, categoryIDs: ids, writer: writer)
            }
        }
        let share = taskShare(for: entries[index], taskID: taskID)
        guard entries[index].goalID != taskID || entries[index].goalShare != share else { return }
        let revision = nextRevision(writer: writer)
        entries[index].goalID = taskID; entries[index].goalShare = share; entries[index].revision = revision
    }

    func taskShare(for entry: CheckIn, taskID: String?) -> Double? {
        guard let taskID, let task = captures.first(where: { $0.id == taskID }) else { return nil }
        let categories = categoryIDs(for: task)
        if categories.isEmpty { return 1 }
        let family = Set(categories.flatMap { [$0] + descendants(of: $0).map(\.id) })
        let ids = allocationCategoryIDs(for: entry)
        return ids.isEmpty ? 0 : Double(ids.filter(family.contains).count) / Double(ids.count)
    }

    public func taskLoggedMinutes(now: Date = Date(), calendar: Calendar = .current) -> [String: Double] {
        let linked = activeEntries.filter { $0.goalID != nil }
        guard let first = linked.map(\.start).min(), first < now else { return [:] }
        let byID = Dictionary(linked.map { ($0.id, $0) }, uniquingKeysWith: { $0.revision < $1.revision ? $1 : $0 })
        var totals: [String: Double] = [:]
        let cal = reportingCalendar(calendar)
        for day in activityDays(from: first, through: now, calendar: cal) {
            for segment in inferredSegments(on: day, now: now, calendar: cal) {
                guard let entry = byID[segment.sampleID], let id = entry.goalID else { continue }
                totals[id, default: 0] += segment.minutes * (entry.goalShare ?? taskShare(for: entry, taskID: id) ?? 1)
            }
        }
        return totals
    }

    /// Reuse the proven workday pacing calculation; the source of truth is Capture.
    public func focusTaskProgress(now: Date = Date(), calendar: Calendar = .current) -> [DatedGoalProgress] {
        let totals = taskLoggedMinutes(now: now, calendar: calendar)
        return focusTasks(now: now).map { task in
            let plan = task.workPlan!
            let goal = DatedGoal(id: task.id, name: task.text, categoryID: categoryIDs(for: task).first,
                targetMinutes: plan.estimatedMinutes!, startDate: plan.startDate ?? task.createdAt, deadline: task.timing!.dueAt!,
                dayStartMinute: plan.dayStartMinute, dayEndMinute: plan.dayEndMinute, timeZoneIdentifier: plan.timeZoneIdentifier,
                deleted: false, revision: task.revision)
            return progress(for: goal, minutes: totals[task.id, default: 0], now: now)
        }
    }
}
