import Foundation

public struct RankingPair: Equatable, Sendable {
    public var first: String
    public var second: String
    public var revision: Revision? = nil
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
    // Recover candidates parked by the earlier first-look flow without
    // discarding their comparisons. Finish these before taking a fresh idea.
    var deferred: [String]?
    var replenishing = false
}

private struct PreferenceGraph {
    var edges: [String: [String]] = [:]
    init(_ preferences: [InboxPreference]) {
        for edge in preferences { edges[edge.winner, default: []].append(edge.loser) }
    }
    func below(_ id: String) -> Set<String> {
        var result = Set<String>(), pending = edges[id] ?? []
        while let next = pending.popLast() {
            if result.insert(next).inserted { pending.append(contentsOf: edges[next] ?? []) }
        }
        return result
    }
    func winner(_ a: String, _ b: String) -> String? {
        if below(a).contains(b) { return a }
        if below(b).contains(a) { return b }
        return nil
    }
}

public struct InboxRanking: Codable, Equatable, Sendable {
    // Legacy fields remain decodable; migration keeps every known ordering edge.
    public var ordered: [String] = []
    public var merge: MergeRanking?
    public var insertion: InsertionRanking?
    public var topTen: TopTenRanking?
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

    mutating func queueReturnedIdeas(_ ids: [String]) {
        guard isActive else { return }
        let seen = seenIDs(), evaluated = Set(ordered + (topTen?.backlog ?? []))
        let returned = ids.filter { !seen.contains($0) && !evaluated.contains($0) && topTen?.candidate?.item != $0 }
        let waiting = topTen?.pending ?? []
        topTen?.pending = returned + waiting.filter { !returned.contains($0) }
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
        }
        if let tournament = state.tournament, let next = tournament.remaining.first {
            return RankingPair(first: tournament.champion, second: next, revision: revision)
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
    }

    func backlogIDs(ids: [String]) -> [String] {
        let active = Set(ids), ranked = Set(ordered)
        return (topTen?.backlog ?? []).filter { active.contains($0) && !ranked.contains($0) }
    }
    func newIDs(ids: [String]) -> [String] {
        let evaluated = Set(ordered + (topTen?.backlog ?? []))
        return ids.filter { !evaluated.contains($0) }
    }
    func challengers(ids: [String]) -> [String] {
        let graph = PreferenceGraph(topTen?.preferences ?? [])
        var pool = backlogIDs(ids: ids)
        if ordered.count == 10, let threshold = ordered.last {
            let screened = graph.below(threshold)
            pool.removeAll { screened.contains($0) }
        }
        // A known loser to another eligible backlog item cannot be the best.
        // Prune it before the tournament, regardless of its arrival/list order.
        let eligible = Set(pool)
        let dominated = pool.reduce(into: Set<String>()) { $0.formUnion(graph.below($1).intersection(eligible)) }
        return pool.filter { !dominated.contains($0) }
    }
    var isActive: Bool {
        guard let state = topTen else { return false }
        return state.candidate != nil || state.tournament != nil || !state.pending.isEmpty || !(state.deferred?.isEmpty ?? true) || state.replenishing
    }

    mutating func startSession(ids: [String]) {
        normalize(ids: ids)
        if !isActive {
            // Snapshot waiting ideas without a session-size limit. New arrivals
            // remain available for the next explicit session, never replacing a pair.
            let seen = seenIDs(), waiting = newIDs(ids: ids)
            topTen?.pending = waiting.filter { !seen.contains($0) }
            topTen?.deferred = waiting.filter { seen.contains($0) }
        }
        advance(ids: ids)
    }
    mutating func replenish(ids: [String]) {
        normalize(ids: ids)
        if !isActive { topTen?.replenishing = true }
        advance(ids: ids)
    }

    /// Advance only already-authorized work. Never starts another new-idea batch.
    mutating func advance(ids: [String]) {
        normalize(ids: ids)
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
            if var tournament = topTen?.tournament {
                if let next = tournament.remaining.first {
                    guard let winner = PreferenceGraph(topTen?.preferences ?? []).winner(tournament.champion, next) else { return }
                    tournament.remaining.removeFirst(); tournament.champion = winner
                    topTen?.tournament = tournament
                } else {
                    topTen?.tournament = nil
                    topTen?.candidate = TopTenInsertion(item: tournament.champion, base: ordered, high: ordered.count, screening: ordered.count == 10)
                }
                continue
            }
            if topTen?.replenishing == true {
                let pool = challengers(ids: ids)
                if let first = pool.first {
                    topTen?.tournament = BacklogTournament(champion: first, remaining: Array(pool.dropFirst()))
                    continue
                }
                topTen?.replenishing = false
            }
            if let next = topTen?.deferred?.first {
                topTen?.deferred?.removeFirst()
                // This candidate already had a first comparison. Search the
                // current list directly, reusing its answers even if #10 changed.
                // Inserting at index 10 naturally returns it to the backlog.
                topTen?.candidate = TopTenInsertion(item: next, base: ordered, high: ordered.count, screening: false)
                continue
            }
            if let next = topTen?.pending.first {
                topTen?.pending.removeFirst()
                topTen?.candidate = TopTenInsertion(item: next, base: ordered, high: ordered.count, screening: ordered.count == 10)
                continue
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
        }
    }

    mutating func rerank(_ id: String, ids: [String]) {
        normalize(ids: ids)
        ordered.removeAll { $0 == id }
        topTen?.backlog.removeAll { $0 == id }
        topTen?.preferences.removeAll { $0.winner == id || $0.loser == id }
        // Interrupted candidates remain discoverable in New Ideas or Backlog.
        topTen?.candidate = nil; topTen?.tournament = nil
        topTen?.deferred = nil
        topTen?.replenishing = false; topTen?.pending = [id]
        advance(ids: ids)
    }
}

extension Ledger {
    public var activeCaptures: [Capture] { activeCaptures(at: Date()) }
    public func activeCaptures(at now: Date) -> [Capture] {
        captures.filter { $0.deletedAt == nil && !$0.isDone && !$0.isSnoozed(at: now) }
    }
    public var snoozedCaptures: [Capture] { snoozedCaptures(at: Date()) }
    public func snoozedCaptures(at now: Date) -> [Capture] {
        captures.filter { $0.deletedAt == nil && !$0.isDone && $0.isSnoozed(at: now) }.sorted {
            $0.snoozedUntil == $1.snoozedUntil ? $0.id < $1.id : $0.snoozedUntil! < $1.snoozedUntil!
        }
    }
    private var rankingIDs: [String] {
        activeCaptures.sorted {
            // Returned ideas get first review; creation dates never change.
            if ($0.snoozedUntil != nil) != ($1.snoozedUntil != nil) { return $0.snoozedUntil != nil }
            if let a = $0.snoozedUntil, let b = $1.snoozedUntil, a != b { return a < b }
            return $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }.map(\.id)
    }
    private var rankingProjection: InboxRanking {
        var ranking = inboxRanking ?? InboxRanking()
        ranking.normalize(ids: rankingIDs)
        ranking.resetSnoozedReviews(captures)
        ranking.normalize(ids: rankingIDs)
        return ranking
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
    public var needsTopTenReplenishment: Bool { !rankingProjection.challengers(ids: rankingIDs).isEmpty }
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
        ranking.queueReturnedIdeas(activeCaptures.filter { $0.snoozedUntil != nil }.sorted { $0.snoozedUntil! < $1.snoozedUntil! }.map(\.id))
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
        ranking.apply(preferred); ranking.advance(ids: rankingIDs)
        ranking.recordPresentation()
        // Every answer advances the revision even if the next pair has the same IDs.
        ranking.revision = nextRevision(writer: writer); inboxRanking = ranking
    }
    public mutating func rerankCapture(_ id: String, writer: String) {
        guard activeCaptures.contains(where: { $0.id == id }) else { return }
        var ranking = rankingProjection
        ranking.rerank(id, ids: rankingIDs); saveRanking(ranking, writer: writer)
    }
    public mutating func snoozeCapture(_ id: String, until: Date, writer: String, now: Date = Date()) {
        guard until > now, let index = captures.firstIndex(where: { $0.id == id && $0.deletedAt == nil && !$0.isDone }) else { return }
        let revision = nextRevision(writer: writer)
        captures[index].snoozedUntil = until
        captures[index].reviewRevision = revision
        captures[index].revision = revision
        normalizeInboxRanking(writer: writer)
    }
    public mutating func bringBackCapture(_ id: String, writer: String, now: Date = Date()) {
        guard let index = captures.firstIndex(where: { $0.id == id && $0.deletedAt == nil && !$0.isDone }),
              captures[index].snoozedUntil != nil else { return }
        let revision = nextRevision(writer: writer)
        captures[index].snoozedUntil = now
        captures[index].reviewRevision = revision
        captures[index].revision = revision
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
