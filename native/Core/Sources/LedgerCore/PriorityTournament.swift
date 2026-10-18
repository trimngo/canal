import Foundation

/// A saved, balanced winner tree. Leaves refer to captures, never copies of
/// their text. Extracting winners is a query, not completion of those captures.
/// Cached branches survive pauses and removals; only affected paths change.
public struct PriorityTournament: Codable, Equatable, Sendable {
    var leaves: [String?]
    var winners: [String?]
    var counts: [Int]
    var confirmed: [String] = []
    var matchup: [String]?

    init(ids: [String]) {
        var capacity = 1
        while capacity < ids.count { capacity *= 2 }
        leaves = ids.map(Optional.some) + Array(repeating: nil, count: capacity - ids.count)
        winners = Array(repeating: nil, count: capacity * 2)
        counts = Array(repeating: 0, count: capacity * 2)
        rebuild()
    }

    var members: Set<String> { Set(leaves.compactMap { $0 }) }
    var isComplete: Bool { confirmed.count == min(10, members.count) }

    mutating func rebuild() {
        winners = Array(repeating: nil, count: leaves.count * 2)
        counts = Array(repeating: 0, count: leaves.count * 2)
        let excluded = Set(confirmed)
        for (index, id) in leaves.enumerated() {
            if let id, !excluded.contains(id) {
                winners[leaves.count + index] = id
                counts[leaves.count + index] = 1
            }
        }
        if leaves.count > 1 {
            for index in stride(from: leaves.count - 1, through: 1, by: -1) {
                counts[index] = counts[index * 2] + counts[index * 2 + 1]
            }
        }
    }

    private mutating func updateLeaf(at index: Int, winner: String?) {
        var node = leaves.count + index
        winners[node] = winner; counts[node] = winner == nil ? 0 : 1
        while node > 1 {
            node /= 2
            winners[node] = nil
            counts[node] = counts[node * 2] + counts[node * 2 + 1]
        }
    }

    /// Removing an item preserves the certified order of surviving winners.
    /// Adding an item invalidates certification, but retains comparison answers.
    mutating func synchronize(ids: [String]) {
        let valid = Set(ids), existing = members
        guard valid != existing else { return }
        if let matchup, matchup.contains(where: { !valid.contains($0) }) { self.matchup = nil }
        confirmed.removeAll { !valid.contains($0) }
        for index in leaves.indices {
            if let id = leaves[index], !valid.contains(id) {
                leaves[index] = nil; updateLeaf(at: index, winner: nil)
            }
        }
        let added = ids.filter { !existing.contains($0) }
        guard !added.isEmpty else { return }
        let extracted = confirmed
        confirmed = []
        for id in extracted {
            if let index = leaves.firstIndex(of: id) { updateLeaf(at: index, winner: id) }
        }
        for id in added {
            if let empty = leaves.firstIndex(of: nil) {
                leaves[empty] = id; updateLeaf(at: empty, winner: id)
            } else {
                leaves += Array(repeating: nil, count: leaves.count)
                leaves[leaves.firstIndex(of: nil)!] = id
                rebuild()
            }
        }
    }

    mutating func invalidateAnswers() {
        confirmed = []; matchup = nil; rebuild()
    }

    /// Resolve cached branches first. An unanswered match pauses the query.
    /// Each extracted winner removes one leaf only in this working tree.
    mutating func advance(limit: Int = 10,
                          knownLeader: (Set<String>) -> String? = { _ in nil },
                          knownWinner: (String, String) -> String?) {
        matchup = nil
        let target = min(limit, members.count)
        var remaining = members.subtracting(confirmed)
        while confirmed.count < target {
            // A known global winner needs no comparisons between its losers.
            // In particular, importing a ranked top ten never sorts its tail.
            let proven = knownLeader(remaining)
            guard let winner = proven ?? resolve(1, knownWinner: knownWinner) else { return }
            confirmed.append(winner)
            remaining.remove(winner)
            if let index = leaves.firstIndex(of: winner) { updateLeaf(at: index, winner: nil) }
        }
    }

    private mutating func resolve(_ node: Int, knownWinner: (String, String) -> String?) -> String? {
        guard counts[node] > 0 else { return nil }
        if let cached = winners[node] { return cached }
        let left = node * 2, right = left + 1
        if counts[left] == 0 {
            guard let winner = resolve(right, knownWinner: knownWinner) else { return nil }
            winners[node] = winner; return winner
        }
        if counts[right] == 0 {
            guard let winner = resolve(left, knownWinner: knownWinner) else { return nil }
            winners[node] = winner; return winner
        }
        guard let a = resolve(left, knownWinner: knownWinner),
              let b = resolve(right, knownWinner: knownWinner) else { return nil }
        guard let winner = knownWinner(a, b) else { matchup = [a, b]; return nil }
        winners[node] = winner
        return winner
    }
}
