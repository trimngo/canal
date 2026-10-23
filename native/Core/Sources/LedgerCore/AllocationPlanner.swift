import Foundation

public enum PlannerError: LocalizedError {
    case invalidHierarchy, conflictingCategories, invalidBudget, invalidTimeZone, calculatedGoal
    public var errorDescription: String? {
        switch self {
        case .invalidHierarchy: return "A category cannot be inside itself or one of its descendants."
        case .conflictingCategories: return "Choose either a parent or its subcategory, not both. Update the affected log or idea labels before making this move."
        case .invalidBudget: return "Enter percentages from 0 to 100, with a total no higher than 100%. Other targets are unchanged."
        case .invalidTimeZone: return "Choose a valid reporting time zone."
        case .calculatedGoal: return "This goal is calculated from its children. Edit a child goal instead."
        }
    }
}

/// Append-only snapshots. No edit mutates a previous intention.
public struct TargetBudget: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var effectiveAt: Date
    public var percentages: [String: Double]
    public var revision: Revision
    /// Nil identifies the original, root-only budget format. New snapshots also
    /// contain nested goals; only these saved roots count toward the total.
    public var topLevelCategoryIDs: [String]? = nil
    /// Editable goals, without calculated parent totals. Keeping these separate
    /// prevents a former parent total becoming a new goal when its last child
    /// moves away. Nil identifies budgets saved before calculated goals.
    public var leafGoalPercentages: [String: Double]? = nil
    public var allocated: Double {
        guard let topLevelCategoryIDs else { return percentages.values.reduce(0, +) }
        return topLevelCategoryIDs.reduce(0) { $0 + percentages[$1, default: 0] }
    }
    public var unallocated: Double { 100 - allocated }
}

public struct AllocationPeriod: Equatable, Sendable {
    public init(trackedMinutes: Double = 0, directMinutes: [String: Double] = [:], representedDays: Int = 0, requestedDays: Int = 1) {
        self.trackedMinutes = trackedMinutes; self.directMinutes = directMinutes
        self.representedDays = representedDays; self.requestedDays = requestedDays
    }
    public var trackedMinutes = 0.0
    public var directMinutes: [String: Double] = [:]
    public var representedDays = 0
    public var requestedDays = 1
    public var sufficient: Bool { representedDays > 0 }
    public func percent(_ minutes: Double) -> Double { trackedMinutes > 0 ? minutes / trackedMinutes * 100 : 0 }
    public func total(for id: String, ledger: Ledger) -> Double {
        let ids = Set([id] + ledger.descendants(of: id).map(\.id))
        return directMinutes.filter { ids.contains($0.key) }.values.reduce(0, +)
    }
}

extension Ledger {
    /// Deterministically detach invalid/cyclic links after concurrent offline moves.
    /// No timestamps, IDs or user revisions are rewritten during reconciliation.
    public var categoryParents: [String: String] {
        let known = Set(categories.map(\.id))
        var parents = Dictionary(categories.compactMap { category -> (String, String)? in
            guard let parent = category.parentID, known.contains(parent), parent != category.id else { return nil }
            return (category.id, parent)
        }, uniquingKeysWith: { first, _ in first })
        for id in known.sorted() {
            var path: [String] = [], node = id
            while let next = parents[node] {
                if let index = path.firstIndex(of: node) {
                    if let detach = path[index...].min() { parents.removeValue(forKey: detach) }
                    break
                }
                path.append(node); node = next
            }
        }
        return parents
    }
    public func children(of parent: String?) -> [LedgerCategory] {
        let parents = categoryParents
        return categories.filter { parents[$0.id] == parent }.sorted {
            if ($0.sortOrder ?? 0) != ($1.sortOrder ?? 0) { return ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
            return $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    public func descendants(of id: String) -> [LedgerCategory] {
        children(of: id).flatMap { [$0] + descendants(of: $0.id) }
    }
    public func categoryPath(_ id: String) -> String {
        guard let category = categories.first(where: { $0.id == id }) else { return "Uncategorized" }
        guard let parent = categoryParents[id] else { return category.name }
        return categoryPath(parent) + " › " + category.name
    }
    public var orderedCategories: [LedgerCategory] {
        children(of: nil).flatMap { [$0] + descendants(of: $0.id) }
    }
    public func categoryConflicts(_ id: String, with selected: [String]) -> [String] {
        let parents = categoryParents
        func ancestor(_ a: String, of b: String) -> Bool {
            var node = b
            while let parent = parents[node] { if parent == a { return true }; node = parent }
            return false
        }
        return selected.filter { $0 != id && (ancestor($0, of: id) || ancestor(id, of: $0)) }
    }
    public func validateCategories(_ ids: [String]) throws {
        let known = Set(categories.map(\.id))
        guard ids.allSatisfy({ known.contains($0) }) else { throw LedgerError.invalidCategory }
        guard ids.allSatisfy({ categoryConflicts($0, with: ids).isEmpty }) else { throw PlannerError.conflictingCategories }
    }
    public func confirmedCategoryIDs(for entry: CheckIn) -> [String] {
        guard entry.categoryAssignment != .automatic else { return [] }
        let known = Set(categories.map(\.id))
        let ids = Array(Set(entry.categoryIDs ?? entry.categoryID.map { [$0] } ?? [])).filter { known.contains($0) }.sorted()
        // Concurrent hierarchy edits can make old selections conflict. Prefer the
        // most specific selection, once, until the user edits that log.
        return ids.filter { id in !ids.contains { other in other != id && descendants(of: id).contains { $0.id == other } } }
    }
    /// Missing/deleted category shares remain Uncategorized, preserving the split.
    public func allocationCategoryIDs(for entry: CheckIn) -> [String] {
        guard entry.categoryAssignment != .automatic else { return ["uncategorized"] }
        let raw = Set(entry.categoryIDs ?? entry.categoryID.map { [$0] } ?? [])
        let known = Set(categories.map(\.id))
        let confirmed = confirmedCategoryIDs(for: entry)
        return confirmed + raw.filter { !known.contains($0) }.map { _ in "uncategorized" }
    }
    public mutating func saveSample(id: String? = nil, at timestamp: Date, activity: String, categoryIDs: [String], writer: String, now: Date = Date()) throws {
        if let id, isLogDeleted(id) { throw LedgerError.deletedSample }
        let text = activity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 500 else { throw LedgerError.invalidActivity }
        guard timestamp.timeIntervalSince1970.isFinite else { throw LedgerError.invalidSlot }
        guard timestamp <= now else { throw LedgerError.futureSlot }
        let ids = Array(Set(categoryIDs)).sorted()
        try validateCategories(ids)
        let revision = nextRevision(writer: writer), sampleID = id ?? UUID().uuidString
        var entry = CheckIn(end: timestamp, activity: text, categoryID: ids.first, revision: revision, sampleID: sampleID, categoryAssignment: ids.isEmpty ? .automatic : .manual)
        entry.mood = entries.first(where: { $0.id == sampleID })?.mood
        entry.goalID = entries.first(where: { $0.id == sampleID })?.goalID
        entry.intervalStart = entries.first(where: { $0.id == sampleID })?.intervalStart
        entry.categoryIDs = ids
        entries.removeAll { $0.id == sampleID }; entries.append(entry)
    }
    public mutating func moveCategory(_ id: String, to parent: String?, writer: String) throws {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { throw LedgerError.invalidCategory }
        if let parent {
            guard categories.contains(where: { $0.id == parent }), parent != id, !descendants(of: id).contains(where: { $0.id == parent }) else { throw PlannerError.invalidHierarchy }
        }
        var draft = self
        draft.categories[index].parentID = parent
        // Never silently change an existing valid split through a hierarchy move.
        for entry in activeEntries {
            let ids = confirmedCategoryIDs(for: entry)
            guard ids.allSatisfy({ draft.categoryConflicts($0, with: ids).isEmpty }) else { throw PlannerError.conflictingCategories }
        }
        draft.categories[index].sortOrder = (draft.children(of: parent).compactMap(\.sortOrder).max() ?? 0) + 1
        draft.categories[index].revision = draft.nextRevision(writer: writer)
        try draft.removeIneligibleTargets(writer: writer)
        self = draft
    }
    public mutating func reorderCategories(_ ids: [String], parent: String?, writer: String) throws {
        guard Set(ids) == Set(children(of: parent).map(\.id)), ids.count == Set(ids).count else { throw PlannerError.invalidHierarchy }
        for (order, id) in ids.enumerated() {
            guard let index = categories.firstIndex(where: { $0.id == id }) else { continue }
            categories[index].sortOrder = order; categories[index].revision = nextRevision(writer: writer)
        }
    }
    public func currentBudget(at date: Date = Date()) -> TargetBudget? {
        (targetBudgets ?? []).filter { $0.effectiveAt <= date }.max {
            $0.effectiveAt == $1.effectiveAt ? ($0.revision == $1.revision ? $0.id < $1.id : $0.revision < $1.revision) : $0.effectiveAt < $1.effectiveAt
        }
    }
    public func currentTargets(at date: Date = Date()) -> [String: Double] {
        let top = Set(children(of: nil).map(\.id))
        return (currentBudget(at: date)?.percentages ?? [:]).filter { top.contains($0.key) }
    }
    public static func validateTargets(_ values: [String: Double]) throws {
        guard values.values.allSatisfy({ $0.isFinite && (0...100).contains($0) }), values.values.reduce(0, +) <= 100 + 0.0000001 else { throw PlannerError.invalidBudget }
    }
    public mutating func saveTargets(_ values: [String: Double], effectiveAt: Date = Date(), writer: String) throws {
        try Self.validateTargets(values)
        let top = Set(children(of: nil).map(\.id))
        guard values.keys.allSatisfy({ top.contains($0) }), effectiveAt.timeIntervalSince1970.isFinite else { throw PlannerError.invalidBudget }
        guard currentBudget(at: effectiveAt)?.percentages != values else { return }
        let budget = TargetBudget(id: UUID().uuidString, effectiveAt: effectiveAt, percentages: values, revision: nextRevision(writer: writer))
        targetBudgets = (targetBudgets ?? []) + [budget]
    }
    mutating func removeIneligibleTargets(writer: String) throws {
        let now = Date()
        guard let current = currentBudget(at: now) else { return }
        if current.topLevelCategoryIDs != nil {
            try saveAllocationGoals(currentGoals(at: now), effectiveAt: now, writer: writer)
            return
        }
        let next = currentTargets(at: now)
        if next != current.percentages { try saveTargets(next, effectiveAt: now, writer: writer) }
    }
    public func reportingCalendar(_ calendar: Calendar = .current) -> Calendar {
        var result = calendar
        if let id = settings.reportingTimeZoneIdentifier, let zone = TimeZone(identifier: id) { result.timeZone = zone }
        return result
    }
    public func reportingDay(containing date: Date, calendar: Calendar = .current) -> Date {
        reportingCalendar(calendar).startOfDay(for: date)
    }
    /// Calendar boundaries include the entire local date (23/24/25 hours at DST).
    public func dayBounds(on day: Date, calendar: Calendar = .current) -> DateInterval? {
        reportingCalendar(calendar).dateInterval(of: .day, for: day)
    }
    public func daySamples(on day: Date, now: Date = Date(), calendar: Calendar = .current) -> [CheckIn] {
        guard let bounds = dayBounds(on: day, calendar: calendar) else { return [] }
        return activeEntries.filter { $0.intervalStart == nil && $0.end >= bounds.start && $0.end < bounds.end && $0.end <= now }.sorted { $0.end == $1.end ? $0.id < $1.id : $0.end < $1.end }
    }
    func estimatedSampleSegments(on day: Date, now: Date, calendar: Calendar, method: InferenceMethod?) -> [InferredSegment] {
        guard let bounds = dayBounds(on: day, calendar: calendar), now > bounds.start else { return [] }
        let cutoff = min(bounds.end, now)
        let distinct = Dictionary(daySamples(on: day, now: now, calendar: calendar).map { ($0.end, $0) }, uniquingKeysWith: {
            if $0.revision == $1.revision { return $0.id < $1.id ? $1 : $0 }
            return $0.revision < $1.revision ? $1 : $0
        }).values.sorted { $0.end < $1.end }
        let rule = method ?? settings.inferenceMethod
        func midpoint(_ a: Date, _ b: Date) -> Date { a.addingTimeInterval(b.timeIntervalSince(a) / 2) }
        return distinct.indices.compactMap { index in
            let sample = distinct[index]
            // Extrapolate half the configured mean notification interval at
            // either edge; missed/random prompts never stretch the tail.
            let padding = settings.sampleBoundaryPadding
            let start = index == 0 ? max(bounds.start, sample.end.addingTimeInterval(-padding)) : (rule == .carryForward ? sample.end : midpoint(distinct[index - 1].end, sample.end))
            let end = index == distinct.count - 1 ? min(cutoff, sample.end.addingTimeInterval(padding)) : (rule == .carryForward ? distinct[index + 1].end : midpoint(sample.end, distinct[index + 1].end))
            guard end > start else { return nil }
            return InferredSegment(sampleID: sample.id, start: start, end: end, categoryID: confirmedCategoryID(for: sample))
        }
    }
    public func allocation(on day: Date, now: Date = Date(), calendar: Calendar = .current, clippingTo interval: DateInterval? = nil) -> AllocationPeriod {
        let segments = inferredSegments(on: day, now: now, calendar: calendar)
        guard !segments.isEmpty else { return AllocationPeriod() }
        let samples = Dictionary(activeEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var period = AllocationPeriod()
        for segment in segments {
            guard let sample = samples[segment.sampleID] else { continue }
            let start = max(segment.start, interval?.start ?? segment.start)
            let end = min(segment.end, interval?.end ?? segment.end)
            guard end > start else { continue }
            let minutes = end.timeIntervalSince(start) / 60
            let choices = allocationCategoryIDs(for: sample)
            let ids = choices.isEmpty ? ["uncategorized"] : choices
            for id in ids { period.directMinutes[id, default: 0] += minutes / Double(ids.count) }
            period.trackedMinutes += minutes
        }
        period.representedDays = period.trackedMinutes > 0 ? 1 : 0
        return period
    }
    public func rollingAllocation(now: Date = Date(), calendar: Calendar = .current) -> AllocationPeriod {
        let cal = reportingCalendar(calendar), today = reportingDay(containing: now, calendar: cal)
        var result = AllocationPeriod(); result.requestedDays = 7
        for offset in -6...0 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let period = allocation(on: day, now: now, calendar: cal)
            result.trackedMinutes += period.trackedMinutes; result.representedDays += period.representedDays
            for (id, minutes) in period.directMinutes { result.directMinutes[id, default: 0] += minutes }
        }
        return result
    }
}
