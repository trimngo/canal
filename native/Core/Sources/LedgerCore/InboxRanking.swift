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
    // Nil in older backups. Legacy insertion bounds become saved answers once.
    public var tournamentVersion: Int?
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
            let visible = priorityTournament?.matchup
            priorityTournament?.invalidateAnswers()
            if let visible, !visible.contains(id) { priorityTournament?.matchup = visible }
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
        guard let matchup = priorityTournament?.matchup, matchup.count == 2 else { return nil }
        return RankingPair(first: matchup[0], second: matchup[1], revision: revision)
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
        if topTen == nil { topTen = TopTenRanking() }
        if tournamentVersion == nil {
            // Retain the complete old ordering, including positions below ten.
            rememberChain(ordered)
            for old in [insertion, topTen?.candidate.map {
                InsertionRanking(item: $0.item, base: $0.base, low: $0.low, high: $0.high)
            }].compactMap({ $0 }) {
                rememberChain(old.base)
                if old.low > 0, old.low <= old.base.count { remember(old.base[old.low - 1], old.item) }
                if old.high >= 0, old.high < old.base.count { remember(old.item, old.base[old.high]) }
                if ordered.isEmpty { ordered = old.base }
            }
            if let old = merge {
                for run in old.runs + old.nextRuns { rememberChain(run) }
                rememberChain(old.merged + old.left)
                rememberChain(old.merged + old.right)
            }
            let wasActive = merge != nil || insertion != nil || topTen?.candidate != nil ||
                topTen?.tournament != nil || !(topTen?.pending.isEmpty ?? true) ||
                !(topTen?.deferred?.isEmpty ?? true) || topTen?.replenishing == true
            // Keep a previously visible tournament match through migration.
            if let old = topTen?.tournament, let next = old.remaining.first {
                if priorityTournament == nil { priorityTournament = PriorityTournament(ids: ids) }
                priorityTournament?.matchup = [old.champion, next]
            }
            merge = nil; insertion = nil
            topTen?.candidate = nil; topTen?.tournament = nil
            topTen?.pending = []; topTen?.deferred = nil
            topTen?.replenishing = wasActive || priorityTournament?.matchup != nil
            tournamentVersion = 1
        }
        let valid = Set(ids)
        var seen = Set<String>()
        let previous = ordered.filter { seen.insert($0).inserted }
        ordered = Array(previous.filter(valid.contains).prefix(10))
        for id in previous where !ordered.contains(id) {
            if !(topTen?.backlog.contains(id) ?? false) { topTen?.backlog.append(id) }
        }
        topTen?.backlog.removeAll { ordered.contains($0) }
        // New captures cannot replace a comparison currently on screen.
        // Refresh membership after an answer or an explicit Review tap.
        if var tree = priorityTournament, pair == nil || !valid.isSuperset(of: tree.matchup ?? []) {
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
        if !newIDs(ids: ids).isEmpty { return true }
        let backlog = backlogIDs(ids: ids)
        guard !backlog.isEmpty else { return false }
        guard ordered.count == 10, let threshold = ordered.last else { return true }
        let excluded = PreferenceGraph(topTen?.preferences ?? []).below(threshold)
        return backlog.contains { !excluded.contains($0) }
    }
    var isActive: Bool { topTen?.replenishing == true || pair != nil }

    mutating func startSession(ids: [String]) {
        normalize(ids: ids)
        priorityTournament?.matchup = nil
        topTen?.replenishing = true
        advance(ids: ids, includeNewIdeas: true)
    }
    mutating func replenish(ids: [String]) { startSession(ids: ids) }

    /// All ideas use the same saved winner tree. Passive refreshes preserve the
    /// visible question; answers and explicit Review refresh newest-first order.
    mutating func advance(ids: [String], includeNewIdeas: Bool = false) {
        normalize(ids: ids)
        if !includeNewIdeas, pair != nil { return }
        guard includeNewIdeas || isActive else { return }
        var tree = priorityTournament ?? PriorityTournament(ids: ids)
        tree.synchronize(ids: ids)
        let graph = PreferenceGraph(topTen?.preferences ?? [])
        tree.advance(reviewOrder: ids, knownLeader: { graph.soleLeader(in: $0) }) { graph.winner($0, $1) }
        priorityTournament = tree
        // Keep the existing shortlist visible while a newly confirmed prefix
        // replaces it. Never claim a globally verified top ten until complete.
        let old = ordered
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

    mutating func apply(_ preferred: String) {
        guard let pair, preferred == pair.first || preferred == pair.second else { return }
        remember(preferred, preferred == pair.first ? pair.second : pair.first)
        priorityTournament?.matchup = nil
    }

    mutating func rerank(_ id: String, ids: [String]) {
        normalize(ids: ids)
        ordered.removeAll { $0 == id }
        topTen?.backlog.removeAll { $0 == id }
        topTen?.preferences.removeAll { $0.winner == id || $0.loser == id }
        topTen?.presented?.removeAll { $0 == id }
        priorityTournament?.invalidateAnswers()
        startSession(ids: [id] + ids.filter { $0 != id })
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
            let a = $0.rankingArrivalDate(), b = $1.rankingArrivalDate()
            return a == b ? $0.id < $1.id : a > b
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
        // Save the answer, then let the tournament choose the next unresolved match.
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
        captures[index].returnedAt = nil
        captures[index].snoozedUntil = until
        captures[index].reviewRevision = revision
        captures[index].revision = revision
        normalizeInboxRanking(writer: writer)
    }
    public mutating func bringBackCapture(_ id: String, writer: String, now: Date = Date()) {
        guard let index = captures.firstIndex(where: { $0.id == id && $0.deletedAt == nil && !$0.isDone && $0.isReference != true }),
              captures[index].snoozedUntil != nil else { return }
        let revision = nextRevision(writer: writer)
        captures[index].returnedAt = now
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
        captures[index].returnedAt = nil
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
