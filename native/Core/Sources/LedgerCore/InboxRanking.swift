import Foundation

public struct RankingPair: Equatable, Sendable {
    public var first: String
    public var second: String
    public var revision: Revision? = nil
}

/// One coherent projection for a screen render. Computing each list separately
/// used to repeatedly normalize and traverse the same preference graph per row.
public struct InboxRankingSnapshot: Equatable, Sendable {
    public var ranked: [Capture]
    public var unseen: [Capture]
    public var inProgress: [Capture]
    public var backlog: [Capture]
    public var pair: RankingPair?
    public var isActive: Bool
    public var needsReview: Bool
    public var isVerified: Bool
    public var confirmedCount: Int
    public var isTournamentReview: Bool
    public var unrankedCount: Int { unseen.count + inProgress.count }
}

public struct MergeRanking: Codable, Equatable, Sendable {
    var runs: [[String]]
    var nextRuns: [[String]] = []
    var left: [String] = []
    var right: [String] = []
    var merged: [String] = []


}

public struct InsertionRanking: Codable, Equatable, Sendable {
    var item: String
    var base: [String]
    var low = 0
    var high: Int
}

// Only direct answers and known sorted chains are retained. Transitive answers
// let replenishment reuse earlier work without sorting the backlog.
public struct InboxPreference: Codable, Equatable, Sendable {
    var winner: String
    var loser: String
}

public struct TopTenInsertion: Codable, Equatable, Sendable {
    var item: String
    var base: [String]
    var low = 0
    var high: Int
    var screening: Bool
}

public struct BacklogTournament: Codable, Equatable, Sendable {
    var champion: String
    var remaining: [String]
}

public struct TopTenRanking: Codable, Equatable, Sendable {
    var backlog: [String] = []
    var preferences: [InboxPreference] = []
    var candidate: TopTenInsertion?
    var tournament: BacklogTournament?
    var pending: [String] = []
    // Optional for ledgers saved before separate unseen/in-progress queues.
    var presented: [String]? = []
    // Decode parked candidates from earlier versions. Their saved answers are
    // reused when they reach the front of the creation-date queue.
    var deferred: [String]?
    var replenishing = false
}

private final class PreferenceGraph {
    var edges: [String: [String]] = [:]
    private var descendants: [String: Set<String>] = [:]
    init(_ preferences: [InboxPreference]) {
        for edge in preferences { edges[edge.winner, default: []].append(edge.loser) }
    }
    func below(_ id: String) -> Set<String> {
        if let cached = descendants[id] { return cached }
        var result = Set<String>(), pending = edges[id] ?? []
        while let next = pending.popLast() {
            if result.insert(next).inserted { pending.append(contentsOf: edges[next] ?? []) }
        }
        descendants[id] = result
        return result
    }
    func winner(_ a: String, _ b: String) -> String? {
        if below(a).contains(b) { return a }
        if below(b).contains(a) { return b }
        return nil
    }
    /// Find a proven leader in one graph walk, including paths through inactive
    /// ideas. This avoids asking questions about losers of an already-known
    /// winner, without computing transitive closure separately for every idea.
    func soleLeader(in ids: Set<String>) -> String? {
        var visited = Set<String>(), pending = ids.flatMap { edges[$0] ?? [] }
        while let next = pending.popLast() {
            if visited.insert(next).inserted { pending.append(contentsOf: edges[next] ?? []) }
        }
        let leaders = ids.subtracting(visited)
        return leaders.count == 1 ? leaders.first : nil
    }
}

public struct InboxRanking: Codable, Equatable, Sendable {
    // Legacy fields remain decodable; migration keeps every known ordering edge.
    public var ordered: [String] = []
    public var merge: MergeRanking?
    public var insertion: InsertionRanking?
    public var topTen: TopTenRanking?
    // Optional so every previous ledger, backup and sync record still decodes.
    public var priorityTournament: PriorityTournament?
    // Remember resets independently of ranking's last-write-wins revision. A
    // stale ranking received from another device must not revive old answers.
    public var reviewedSnoozes: [String: Revision]?
    public var revision = Revision()
    public init() {}

    mutating func resetSnoozedReviews(_ captures: [Capture]) {
        for capture in captures {
            guard let review = capture.reviewRevision,
                  reviewedSnoozes?[capture.id] != review else { continue }
            let id = capture.id
            ordered.removeAll { $0 == id }
            topTen?.backlog.removeAll { $0 == id }
            topTen?.preferences.removeAll { $0.winner == id || $0.loser == id }
            priorityTournament?.invalidateAnswers()
            topTen?.presented?.removeAll { $0 == id }
            topTen?.pending.removeAll { $0 == id }
            topTen?.deferred?.removeAll { $0 == id }
            if topTen?.candidate?.item == id { topTen?.candidate = nil }
            if var tournament = topTen?.tournament {
                tournament.remaining.removeAll { $0 == id }
                if tournament.champion == id {
                    if let next = tournament.remaining.first {
                        tournament.champion = next; tournament.remaining.removeFirst()
                        topTen?.tournament = tournament
                    } else { topTen?.tournament = nil }
                } else { topTen?.tournament = tournament }
            }
            if let old = insertion, old.item == id { insertion = nil }
            if reviewedSnoozes == nil { reviewedSnoozes = [:] }
            reviewedSnoozes?[id] = review
        }
    }

    public var pair: RankingPair? {
        guard let state = topTen else { return nil }
        if let candidate = state.candidate {
            if candidate.screening, let threshold = candidate.base.last {
                return RankingPair(first: candidate.item, second: threshold, revision: revision)
            }
            if candidate.low < candidate.high {
                return RankingPair(first: candidate.item, second: candidate.base[(candidate.low + candidate.high) / 2], revision: revision)
            }
            // A backlog tournament can be paused behind a newer candidate.
            // Settle that candidate before exposing the tournament's pair.
            return nil
        }
        if let tournament = state.tournament, let next = tournament.remaining.first {
            return RankingPair(first: tournament.champion, second: next, revision: revision)
        }
        if let matchup = priorityTournament?.matchup, matchup.count == 2 {
            return RankingPair(first: matchup[0], second: matchup[1], revision: revision)
        }
        return nil
    }

    private mutating func remember(_ winner: String, _ loser: String) {
        guard winner != loser, var state = topTen else { return }
        let edge = InboxPreference(winner: winner, loser: loser)
        if !state.preferences.contains(edge) { state.preferences.append(edge) }
        topTen = state
    }
    private mutating func rememberChain(_ ids: [String]) {
        for (a, b) in zip(ids, ids.dropFirst()) { remember(a, b) }
    }

    mutating func recordPresentation() {
        guard let pair else { return }
        var seen = Set(topTen?.presented ?? [])
        seen.insert(pair.first); seen.insert(pair.second)
        topTen?.presented = seen.sorted()
    }

    func seenIDs() -> Set<String> {
        var seen = Set(topTen?.presented ?? [])
        for edge in topTen?.preferences ?? [] { seen.insert(edge.winner); seen.insert(edge.loser) }
        // Older saves did not record presentation separately. Their active
        // pair is the best available evidence of what had already been shown.
        if topTen?.presented == nil, let pair { seen.insert(pair.first); seen.insert(pair.second) }
        return seen
    }

    mutating func normalize(ids: [String]) {
        if topTen == nil {
            topTen = TopTenRanking()
            rememberChain(ordered)
            if let old = insertion {
                rememberChain(old.base)
                if old.low > 0, old.low <= old.base.count { remember(old.base[old.low - 1], old.item) }
                if old.high >= 0, old.high < old.base.count { remember(old.item, old.base[old.high]) }
                ordered = old.base
                topTen?.pending = [old.item]
            }
            if let old = merge {
                for run in old.runs + old.nextRuns { rememberChain(run) }
                rememberChain(old.merged + old.left)
                rememberChain(old.merged + old.right)
                // Resume all remaining work from the unfinished legacy session.
                topTen?.pending = ids.filter { !ordered.contains($0) }
            }
            merge = nil; insertion = nil
        }
        let valid = Set(ids)
        var seen = Set<String>()
        let previous = ordered.filter { seen.insert($0).inserted }
        let active = previous.filter(valid.contains)
        ordered = Array(active.prefix(10))
        for id in previous where !ordered.contains(id) {
            if !(topTen?.backlog.contains(id) ?? false) { topTen?.backlog.append(id) }
        }
        topTen?.backlog.removeAll { ordered.contains($0) }
        let evaluated = Set(ordered + (topTen?.backlog ?? []))
        topTen?.pending.removeAll { !valid.contains($0) || evaluated.contains($0) }
        topTen?.deferred?.removeAll { !valid.contains($0) || evaluated.contains($0) }
        if var candidate = topTen?.candidate {
            if !valid.contains(candidate.item) || ordered.contains(candidate.item) { topTen?.candidate = nil }
            else if candidate.base != ordered {
                candidate.base = ordered; candidate.low = 0; candidate.high = ordered.count
                candidate.screening = ordered.count == 10
                topTen?.candidate = candidate
            }
        }
        if var tournament = topTen?.tournament {
            tournament.remaining.removeAll { !valid.contains($0) || ordered.contains($0) }
            if !valid.contains(tournament.champion) || ordered.contains(tournament.champion) {
                if let next = tournament.remaining.first {
                    tournament.champion = next; tournament.remaining.removeFirst()
                } else { topTen?.tournament = nil }
            }
            if topTen?.tournament != nil { topTen?.tournament = tournament }
        }
        rememberChain(ordered)
        // Retire the old sequential backlog scan. Its completed answers already
        // live in preferences; a visible legacy match remains valid once.
        if let old = topTen?.tournament {
            if priorityTournament == nil { priorityTournament = PriorityTournament(ids: ids) }
            if let next = old.remaining.first { priorityTournament?.matchup = [old.champion, next] }
            topTen?.tournament = nil
            topTen?.replenishing = true
        }
        // Preserve a visible comparison when captures arrive in the background.
        // Membership is refreshed at the next explicit Continue or answer.
        if var tree = priorityTournament, pair == nil || !Set(ids).isSuperset(of: tree.matchup ?? []) {
            tree.synchronize(ids: ids); priorityTournament = tree
        }
    }

    func backlogIDs(ids: [String]) -> [String] {
        let active = Set(ids), ranked = Set(ordered)
        return (topTen?.backlog ?? []).filter { active.contains($0) && !ranked.contains($0) }
    }
    func newIDs(ids: [String]) -> [String] {
        let evaluated = Set(ordered + (topTen?.backlog ?? []))
        return ids.filter { !evaluated.contains($0) }
    }
    func needsReview(ids: [String]) -> Bool {
        let backlog = backlogIDs(ids: ids)
        guard !backlog.isEmpty else { return false }
        guard ordered.count == 10, let threshold = ordered.last else { return true }
        let excluded = PreferenceGraph(topTen?.preferences ?? []).below(threshold)
        return backlog.contains { !excluded.contains($0) }
    }
    var isActive: Bool {
        guard let state = topTen else { return false }
        return state.candidate != nil || state.tournament != nil || !state.pending.isEmpty || !(state.deferred?.isEmpty ?? true) || state.replenishing
    }

    mutating func startSession(ids: [String]) {
        normalize(ids: ids)
        let waiting = newIDs(ids: ids)
        if let newest = waiting.first {
            // Explicit Continue refreshes the queue. A paused older candidate
            // remains discoverable; its saved answers reconstruct its bounds.
            if topTen?.candidate?.item != newest { topTen?.candidate = nil }
            let current = topTen?.candidate?.item
            topTen?.pending = waiting.filter { $0 != current }
            topTen?.deferred = nil
        }
        // A new candidate can pause tournament review without losing its tree.
        priorityTournament?.matchup = nil
        topTen?.replenishing = true
        advance(ids: ids, includeNewIdeas: true)
    }
    mutating func replenish(ids: [String]) {
        normalize(ids: ids)
        if !newIDs(ids: ids).isEmpty { startSession(ids: ids); return }
        if !isActive { topTen?.replenishing = true }
        advance(ids: ids)
    }

    /// Keep a visible comparison stable. Between candidates, refresh eligible
    /// ideas in date order so a running session never drains an old snapshot.
    /// Passive normalization of an idle inbox cannot start ranking.
    mutating func advance(ids: [String], includeNewIdeas: Bool = false) {
        normalize(ids: ids)
        if !includeNewIdeas, topTen?.candidate == nil, priorityTournament?.matchup != nil { return }
        let activeSession = includeNewIdeas || isActive
        while true {
            if var candidate = topTen?.candidate {
                if !candidate.screening {
                    let graph = PreferenceGraph(topTen?.preferences ?? [])
                    for (index, id) in candidate.base.enumerated() {
                        if let winner = graph.winner(candidate.item, id) {
                            if winner == candidate.item { candidate.high = min(candidate.high, index) }
                            else { candidate.low = max(candidate.low, index + 1) }
                        }
                    }
                    topTen?.candidate = candidate
                }
                if let pair {
                    guard let winner = PreferenceGraph(topTen?.preferences ?? []).winner(pair.first, pair.second) else { return }
                    apply(winner)
                } else {
                    ordered.insert(candidate.item, at: min(candidate.low, ordered.count))
                    topTen?.backlog.removeAll { $0 == candidate.item }
                    if ordered.count > 10 {
                        let displaced = ordered.removeLast()
                        if !(topTen?.backlog.contains(displaced) ?? false) { topTen?.backlog.append(displaced) }
                    }
                    topTen?.candidate = nil
                    rememberChain(ordered)
                }
                continue
            }
            if activeSession && (topTen?.tournament == nil || includeNewIdeas) {
                let waiting = newIDs(ids: ids)
                topTen?.pending = Array(waiting.dropFirst())
                topTen?.deferred = nil
                if let next = waiting.first {
                    topTen?.candidate = TopTenInsertion(item: next, base: ordered, high: ordered.count, screening: ordered.count == 10)
                    continue
                }
            }
            if activeSession {
                var tree = priorityTournament ?? PriorityTournament(ids: ids)
                tree.synchronize(ids: ids)
                let graph = PreferenceGraph(topTen?.preferences ?? [])
                tree.advance(knownLeader: { graph.soleLeader(in: $0) }) { graph.winner($0, $1) }
                priorityTournament = tree
                let old = ordered
                // A confirmed prefix is safe to show immediately; keep the
                // user's remaining priorities visible while review continues.
                ordered = Array((tree.confirmed + old.filter { !tree.confirmed.contains($0) }).prefix(10))
                for id in old where !ordered.contains(id) {
                    if !(topTen?.backlog.contains(id) ?? false) { topTen?.backlog.append(id) }
                }
                topTen?.backlog.removeAll { ordered.contains($0) }
                if tree.isComplete {
                    ordered = tree.confirmed
                    let inactive = (topTen?.backlog ?? []).filter { !ids.contains($0) }
                    topTen?.backlog = inactive + ids.filter { !ordered.contains($0) }
                }
                topTen?.replenishing = !tree.isComplete
            }
            return
        }
    }

    mutating func apply(_ preferred: String) {
        guard let pair, preferred == pair.first || preferred == pair.second else { return }
        remember(preferred, preferred == pair.first ? pair.second : pair.first)
        if var candidate = topTen?.candidate {
            if candidate.screening {
                if preferred == candidate.item {
                    candidate.screening = false; candidate.high = max(0, ordered.count - 1)
                    topTen?.candidate = candidate
                } else {
                    if !(topTen?.backlog.contains(candidate.item) ?? false) { topTen?.backlog.append(candidate.item) }
                    topTen?.candidate = nil
                }
            } else {
                let mid = (candidate.low + candidate.high) / 2
                if preferred == candidate.item { candidate.high = mid } else { candidate.low = mid + 1 }
                topTen?.candidate = candidate
            }
        } else if var tournament = topTen?.tournament {
            tournament.remaining.removeFirst(); tournament.champion = preferred
            topTen?.tournament = tournament
        } else {
            priorityTournament?.matchup = nil
        }
    }

    mutating func rerank(_ id: String, ids: [String]) {
        normalize(ids: ids)
        ordered.removeAll { $0 == id }
        topTen?.backlog.removeAll { $0 == id }
        topTen?.preferences.removeAll { $0.winner == id || $0.loser == id }
        priorityTournament?.invalidateAnswers()
        // Interrupted candidates remain discoverable in New Ideas or Backlog.
        topTen?.candidate = nil; topTen?.tournament = nil
        topTen?.deferred = nil
        topTen?.replenishing = false; topTen?.pending = []
        topTen?.candidate = TopTenInsertion(item: id, base: ordered, high: ordered.count, screening: ordered.count == 10)
        advance(ids: ids)
    }
}

extension Ledger {
    public var activeCaptures: [Capture] { activeCaptures(at: Date()) }
    public func activeCaptures(at now: Date) -> [Capture] {
        captures.filter { $0.deletedAt == nil && !$0.isDone && $0.isReference != true && !$0.isSnoozed(at: now) }
    }
    public var snoozedCaptures: [Capture] { snoozedCaptures(at: Date()) }
    public func snoozedCaptures(at now: Date) -> [Capture] {
        captures.filter { $0.deletedAt == nil && !$0.isDone && $0.isReference != true && $0.isSnoozed(at: now) }.sorted {
            $0.snoozeReturnDate() == $1.snoozeReturnDate() ? $0.id < $1.id : $0.snoozeReturnDate()! < $1.snoozeReturnDate()!
        }
    }
    public var referenceCaptures: [Capture] {
        captures.filter { $0.deletedAt == nil && !$0.isDone && $0.isReference == true }.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }
    }
    private var rankingIDs: [String] {
        activeCaptures.sorted {
            // Returned ideas get first review; creation dates never change.
            if ($0.snoozedUntil != nil) != ($1.snoozedUntil != nil) { return $0.snoozedUntil != nil }
            if let a = $0.snoozeReturnDate(), let b = $1.snoozeReturnDate(), a != b { return a < b }
            return $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }.map(\.id)
    }
    private func rankingProjection(ids: [String]) -> InboxRanking {
        var ranking = inboxRanking ?? InboxRanking()
        ranking.normalize(ids: ids)
        ranking.resetSnoozedReviews(captures)
        ranking.normalize(ids: ids)
        return ranking
    }
    private var rankingProjection: InboxRanking { rankingProjection(ids: rankingIDs) }
    public var inboxSnapshot: InboxRankingSnapshot {
        let ids = rankingIDs, ranking = rankingProjection(ids: ids)
        let byID = Dictionary(activeCaptures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let seen = ranking.seenIDs()
        let pending = ranking.newIDs(ids: ids).compactMap { byID[$0] }
        let backlog = Set(ranking.backlogIDs(ids: ids))
        let review = ranking.needsReview(ids: ids)
        return InboxRankingSnapshot(
            ranked: ranking.ordered.compactMap { byID[$0] },
            unseen: pending.filter { !seen.contains($0.id) },
            inProgress: pending.filter { seen.contains($0.id) },
            backlog: ids.filter { backlog.contains($0) }.compactMap { byID[$0] },
            pair: ranking.pair, isActive: ranking.isActive, needsReview: review,
            isVerified: pending.isEmpty && !review && !ranking.isActive,
            confirmedCount: ranking.priorityTournament?.confirmed.count ?? 0,
            isTournamentReview: ranking.topTen?.candidate == nil && ranking.priorityTournament?.matchup != nil)
    }
    public var rankedCaptureIDs: [String] { rankingProjection.ordered }
    public var rankedCaptures: [Capture] { captures(in: rankedCaptureIDs) }
    public var unrankedCaptures: [Capture] { captures(in: rankingProjection.newIDs(ids: rankingIDs)) }
    public var unseenCaptures: [Capture] {
        let seen = rankingProjection.seenIDs()
        return unrankedCaptures.filter { !seen.contains($0.id) }
    }
    public var partiallyRankedCaptures: [Capture] {
        let seen = rankingProjection.seenIDs()
        return unrankedCaptures.filter { seen.contains($0.id) }
    }
    public var backlogCaptures: [Capture] {
        let backlog = Set(rankingProjection.backlogIDs(ids: rankingIDs))
        return activeCaptures.filter { backlog.contains($0.id) }.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
    }
    public var rankingPair: RankingPair? { rankingProjection.pair }
    public var rankingIsActive: Bool { rankingProjection.isActive }
    public var needsTopTenReplenishment: Bool { rankingProjection.needsReview(ids: rankingIDs) }
    public var topTenIsVerified: Bool { unrankedCaptures.isEmpty && !needsTopTenReplenishment && !rankingIsActive }

    private func captures(in ids: [String]) -> [Capture] {
        let byID = Dictionary(activeCaptures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }
    private mutating func saveRanking(_ ranking: InboxRanking, writer: String) {
        guard ranking != inboxRanking else { return }
        var revised = ranking; revised.revision = nextRevision(writer: writer); inboxRanking = revised
    }
    public mutating func normalizeInboxRanking(writer: String) {
        // A partial companion update can deliver captures before their ranking.
        // Do not mint a newer empty ranking that would shadow the real one.
        guard inboxRanking != nil else { return }
        var ranking = rankingProjection
        ranking.advance(ids: rankingIDs)
        saveRanking(ranking, writer: writer)
    }
    public mutating func prepareRanking(writer: String) {
        normalizeInboxRanking(writer: writer)
        var ranking = rankingProjection
        ranking.startSession(ids: rankingIDs)
        ranking.recordPresentation()
        saveRanking(ranking, writer: writer)
    }
    public mutating func markRankingPresented(writer: String) {
        guard var ranking = inboxRanking else { return }
        ranking.recordPresentation()
        saveRanking(ranking, writer: writer)
    }
    public mutating func replenishTopTen(writer: String) {
        normalizeInboxRanking(writer: writer)
        var ranking = rankingProjection
        ranking.replenish(ids: rankingIDs)
        saveRanking(ranking, writer: writer)
    }
    public mutating func chooseCapture(_ preferred: String, from expected: RankingPair, writer: String) {
        normalizeInboxRanking(writer: writer)
        guard var ranking = inboxRanking, ranking.pair == expected,
              preferred == expected.first || preferred == expected.second else { return }
        ranking.recordPresentation()
        // Keep comparing this candidate until its position is settled. advance
        // updates the top ten before presenting another candidate.
        ranking.apply(preferred); ranking.advance(ids: rankingIDs, includeNewIdeas: true)
        ranking.recordPresentation()
        // Every answer advances the revision even if the next pair has the same IDs.
        ranking.revision = nextRevision(writer: writer); inboxRanking = ranking
    }
    public mutating func rerankCapture(_ id: String, writer: String) {
        guard activeCaptures.contains(where: { $0.id == id }) else { return }
        var ranking = rankingProjection
        ranking.rerank(id, ids: rankingIDs); saveRanking(ranking, writer: writer)
    }
    public mutating func snoozeCapture(_ id: String, until: Date, writer: String, now: Date = Date(), calendar: Calendar = .current) {
        let until = calendar.startOfDay(for: until)
        guard until > now, let index = captures.firstIndex(where: { $0.id == id && $0.deletedAt == nil && !$0.isDone && $0.isReference != true }) else { return }
        let revision = nextRevision(writer: writer)
        captures[index].snoozedUntil = until
        captures[index].reviewRevision = revision
        captures[index].revision = revision
        normalizeInboxRanking(writer: writer)
    }
    public mutating func bringBackCapture(_ id: String, writer: String, now: Date = Date()) {
        guard let index = captures.firstIndex(where: { $0.id == id && $0.deletedAt == nil && !$0.isDone && $0.isReference != true }),
              captures[index].snoozedUntil != nil else { return }
        let revision = nextRevision(writer: writer)
        captures[index].snoozedUntil = now
        captures[index].reviewRevision = revision
        captures[index].revision = revision
        normalizeInboxRanking(writer: writer)
    }
    public mutating func setCaptureReference(_ id: String, reference: Bool, writer: String) {
        guard let index = captures.firstIndex(where: { $0.id == id && $0.deletedAt == nil }),
              (captures[index].isReference == true) != reference else { return }
        let revision = nextRevision(writer: writer)
        captures[index].isReference = reference
        captures[index].snoozedUntil = nil
        captures[index].revision = revision
        // Returning a reference item makes it a new actionable candidate.
        // Moving it out of ranking preserves all other items and their answers.
        if !reference { captures[index].reviewRevision = revision }
        normalizeInboxRanking(writer: writer)
    }
    public mutating func setCaptureDeleted(_ id: String, deleted: Bool, writer: String, now: Date = Date()) {
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        let revision = nextRevision(writer: writer)
        captures[index].deletedAt = deleted ? now : nil
        captures[index].revision = revision
        normalizeInboxRanking(writer: writer)
    }
}
