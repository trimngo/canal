import Foundation

/// Phrase rules and previous explicit choices only. No network or model calls.
public enum OfflineGrouping {
    public static var defaultGroups: [LedgerCategory] {
        [("work", "Work"), ("personal", "Personal Needs"), ("rest", "Rest"),
         ("social", "Socializing"), ("household", "Household & Errands"),
         ("leisure", "Leisure"), ("travel", "Travel")].map { LedgerCategory(id: $0.0, name: $0.1) }
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
            guard let group = groups.first(where: { $0.id == id }) ?? groups.first(where: { normalized($0.name) == normalized(defaultName) }) else { continue }
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
    public func suggestedCategory(for activity: String) -> String? {
        let key = OfflineGrouping.normalized(activity)
        guard !key.isEmpty else { return nil }
        return rememberedChoices()[key]?.categoryID ?? OfflineGrouping.category(for: activity, groups: categories)
    }

    private func rememberedChoices() -> [String: CheckIn] {
        let known = Set(categories.map(\.id))
        var result: [String: CheckIn] = [:]
        for entry in entries where entry.categoryAssignment != .automatic && known.contains(entry.categoryID ?? "") {
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
            guard !categories.contains(where: { $0.id == group.id || OfflineGrouping.normalized($0.name) == OfflineGrouping.normalized(group.name) }) else { continue }
            var added = group; added.revision = nextRevision(writer: writer); categories.append(added)
        }
    }

    public mutating func recategorizeAutomatically(writer: String) {
        let remembered = rememberedChoices()
        var attempted = Set<String>()
        var resolved: [String: String] = [:]
        var counter = nextRevision(writer: writer).counter
        for index in entries.indices {
            let entry = entries[index]
            guard entry.categoryAssignment == .automatic || (entry.categoryAssignment == nil && entry.categoryID == nil) else { continue }
            let key = OfflineGrouping.normalized(entry.activity)
            if attempted.insert(key).inserted {
                resolved[key] = remembered[key]?.categoryID ?? OfflineGrouping.category(for: entry.activity, groups: categories)
            }
            let proposed = resolved[key]
            guard proposed != entry.categoryID else { continue }
            entries[index].categoryID = proposed
            entries[index].categoryAssignment = .automatic
            entries[index].revision = Revision(counter: counter, writer: writer)
            counter += 1
        }
    }
}
