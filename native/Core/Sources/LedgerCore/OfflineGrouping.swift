import Foundation

/// Phrase rules and previous explicit choices only. No network or model calls.
public enum OfflineGrouping {
    public static var defaultGroups: [LedgerCategory] {
        [("work", "Work"), ("personal", "Personal Needs"), ("rest", "Rest"),
         ("social", "Socializing"), ("household", "Household & Errands"),
         ("leisure", "Leisure"), ("travel", "Travel")].map { LedgerCategory(id: $0.0, name: $0.1, automaticRole: $0.0) }
    }

    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static let phrases: [(String, [String])] = [
        ("work", ["work", "working", "preparing classes", "class preparation", "lesson planning", "preparing lessons", "grading", "marking assignments", "teaching", "studying", "studying for", "writing code", "coding", "client call", "client meeting", "team meeting", "answering emails"]),
        ("personal", ["bathroom", "restroom", "toilet", "shower", "showering", "brushing teeth", "getting dressed", "breakfast", "lunch", "dinner", "eating", "coffee", "medication", "doctor", "exercise", "exercising"]),
        ("rest", ["rest", "resting", "nap", "napping", "sleep", "sleeping", "meditating"]),
        ("social", ["socializing", "socialising", "chatting", "with friends", "coffee with", "lunch with", "dinner with", "visiting family", "calling family", "calling a friend", "talking with friends"]),
        ("household", ["cleaning", "laundry", "washing dishes", "doing dishes", "grocery shopping", "groceries", "cooking", "errands", "housework"]),
        ("leisure", ["watching tv", "watching television", "watching a movie", "playing games", "gaming", "reading a novel", "scrolling", "social media", "youtube"]),
        ("travel", ["commuting", "driving", "on the bus", "on a train", "taking the train", "cycling", "walking", "traveling", "travelling"])
    ]

    public static func category(for text: String, groups: [LedgerCategory]) -> String? {
        let value = " " + normalized(text) + " "
        var scores: [String: Int] = [:]
        for (id, choices) in phrases {
            // IDs survive renames. Existing custom groups with a default name
            // can also be used without introducing a duplicate group.
            guard let defaultName = defaultGroups.first(where: { $0.id == id })?.name else { continue }
            guard let group = groups.first(where: { $0.automaticRole == id || $0.id == id }) ?? groups.first(where: { normalized($0.name) == normalized(defaultName) }) else { continue }
            for phrase in choices {
                let phrase = normalized(phrase)
                guard value.contains(" " + phrase + " "), !value.contains(" not " + phrase + " ") else { continue }
                scores[group.id] = max(scores[group.id] ?? 0, phrase.split(separator: " ").count)
            }
        }
        guard let highest = scores.values.max() else { return nil }
        let winners = scores.filter { $0.value == highest }.map(\.key)
        return winners.count == 1 ? winners[0] : nil
    }
}

extension Ledger {
    public func groupEntryCounts(now: Date = Date()) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in activeEntries where entry.end <= now {
            let ids = effectiveCategoryIDs(for: entry)
            var counted = Set<String>()
            for id in ids {
                counted.insert(id)
                var node = id
                while let parent = categoryParents[node] { counted.insert(parent); node = parent }
            }
            if allocationCategoryIDs(for: entry).contains("uncategorized") || ids.isEmpty { counted.insert("uncategorized") }
            for id in counted { counts[id, default: 0] += 1 }
        }
        return counts
    }

    public func confirmedCategoryID(for entry: CheckIn) -> String? {
        confirmedCategoryIDs(for: entry).first
    }

    public func unconfirmedMatches(for activity: String) -> [CheckIn] {
        let key = OfflineGrouping.normalized(activity)
        return activeEntries.filter { confirmedCategoryID(for: $0) == nil && OfflineGrouping.normalized($0.activity) == key }
    }

    public func suggestedCategory(for activity: String) -> String? {
        let key = OfflineGrouping.normalized(activity)
        guard !key.isEmpty else { return nil }
        return rememberedChoices()[key]?.categoryID ?? OfflineGrouping.category(for: activity, groups: categories)
    }

    private func rememberedChoices() -> [String: CheckIn] {
        let known = Set(categories.map(\.id))
        var result: [String: CheckIn] = [:]
        for entry in activeEntries where entry.categoryAssignment != .automatic && known.contains(entry.categoryID ?? "") && confirmedCategoryIDs(for: entry).count == 1 {
            let key = OfflineGrouping.normalized(entry.activity)
            if let previous = result[key] {
                if previous.revision > entry.revision || (previous.revision == entry.revision && previous.id >= entry.id) { continue }
            }
            result[key] = entry
        }
        return result
    }

    public mutating func ensureDefaultGroups(writer: String) {
        for group in OfflineGrouping.defaultGroups {
            if (groupDeletions ?? []).contains(where: { $0.id == group.id || $0.automaticRole == group.id }) { continue }
            if let index = categories.firstIndex(where: { $0.id == group.id || $0.automaticRole == group.id })
                ?? categories.firstIndex(where: { OfflineGrouping.normalized($0.name) == OfflineGrouping.normalized(group.name) }) {
                if categories[index].automaticRole == nil {
                    let revision = nextRevision(writer: writer)
                    categories[index].automaticRole = group.id; categories[index].revision = revision
                }
                continue
            }
            var added = group; added.revision = nextRevision(writer: writer); categories.append(added)
        }
    }

    public mutating func prepareGroupSuggestions(writer _: String) {
        for index in entries.indices {
            let entry = entries[index]
            // Clear cached automatic assignments from previous versions or an
            // older paired device. Suggestions are computed only for display.
            guard entry.categoryAssignment == .automatic && entry.categorySuggestion == nil && entry.categoryID != nil else { continue }
            entries[index].categoryID = nil
            entries[index].categoryIDs = nil
            // This removes an obsolete derived cache, not a user's edit. Keep
            // its revision so an older Watch cannot create a sync ping-pong by
            // restoring that cache and receiving a newer clearing revision.
        }
    }

    public mutating func confirmCategory(for id: String, categoryID: String?, includeMatching: Bool = false, writer: String) throws {
        try confirmCategories(for: id, categoryIDs: categoryID.map { [$0] } ?? [], includeMatching: includeMatching, writer: writer)
    }

    public mutating func confirmCategories(for id: String, categoryIDs: [String], includeMatching: Bool = false, writer: String) throws {
        let ids = Array(Set(categoryIDs)).sorted()
        try validateCategories(ids)
        guard let chosen = activeEntries.first(where: { $0.id == id }) else { return }
        let key = OfflineGrouping.normalized(chosen.activity)
        let selected = Set(activeEntries.filter {
            $0.id == id || (includeMatching && !ids.isEmpty && confirmedCategoryID(for: $0) == nil && OfflineGrouping.normalized($0.activity) == key)
        }.map(\.id))
        var counter = nextRevision(writer: writer).counter
        for index in entries.indices where selected.contains(entries[index].id) {
            let labelsChanged = Set(entries[index].categoryIDs ?? entries[index].categoryID.map { [$0] } ?? []) != Set(ids)
            entries[index].categoryID = ids.first
            entries[index].categoryIDs = ids
            entries[index].categoryAssignment = .manual
            entries[index].categorySuggestion = nil
            if entries[index].goalID != nil, labelsChanged { entries[index].goalShare = datedGoalShare(for: entries[index], goalID: entries[index].goalID) }
            entries[index].revision = Revision(counter: counter, writer: writer); counter += 1
        }
    }
}
