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
    public var oldestBacklogReview: Date?
    public var backlogWithoutReviewDateCount: Int
    public var reviewingBacklog: Bool
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

/// Stored with the ranking revision, so review dates and a paused backlog pass
/// travel through the existing phone/Watch/cloud and backup paths together.
public struct ScreeningReview: Codable, Equatable, Sendable {
    var lastReviewed: [String: Date] = [:]
    var backlogRemaining: [String] = []
    var backlogStarted: [String] = []
    var reviewingBacklog = false
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
    public var screeningReview: ScreeningReview?
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
            rememberChain(ordered)
            screeningReview?.lastReviewed.removeValue(forKey: id)
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
        guard let candidate = topTen?.candidate else { return nil }
        let index = candidate.screening ? candidate.base.count - 1 : (candidate.low + candidate.high) / 2
        guard candidate.screening || candidate.low < candidate.high,
              candidate.base.indices.contains(index) else { return nil }
        return RankingPair(first: candidate.item, second: candidate.base[index], revision: revision)
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
        if screeningReview == nil {
            // Migrate every previous format without inventing review dates.
            // Existing shortlist order and all answered comparisons survive.
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
            let wasActive = isActive || merge != nil || insertion != nil ||
                priorityTournament?.matchup != nil || topTen?.tournament != nil ||
                !(topTen?.pending.isEmpty ?? true) || !(topTen?.deferred?.isEmpty ?? true)
            merge = nil; insertion = nil
            priorityTournament = nil // Decode old trees, but never run a tournament.
            topTen?.candidate = nil; topTen?.tournament = nil
            topTen?.pending = []; topTen?.deferred = nil
            topTen?.replenishing = wasActive
            screeningReview = ScreeningReview()
        }
        let valid = Set(ids)
        var seen = Set<String>()
        let previous = ordered.filter { seen.insert($0).inserted }
        ordered = Array(previous.filter(valid.contains).prefix(10))
        for id in previous where !ordered.contains(id) {
            if !(topTen?.backlog.contains(id) ?? false) { topTen?.backlog.append(id) }
        }
        var backlogSeen = Set<String>()
        let backlog = (topTen?.backlog ?? []).filter { !ordered.contains($0) && backlogSeen.insert($0).inserted }
        topTen?.backlog = backlog
        if let candidate = topTen?.candidate,
           !valid.contains(candidate.item) || candidate.base != ordered || ordered.contains(candidate.item) ||
           candidate.low < 0 || candidate.high > candidate.base.count || candidate.low > candidate.high {
            // Known answers rebuild the insertion bounds if a priority was
            // completed/deleted on either device while a question was visible.
            topTen?.candidate = nil
        }
    }

    func backlogIDs(ids: [String]) -> [String] {
        let active = Set(ids), ranked = Set(ordered)
        return (topTen?.backlog ?? []).filter { active.contains($0) && !ranked.contains($0) }.sorted {
            let a = screeningReview?.lastReviewed[$0], b = screeningReview?.lastReviewed[$1]
            if a != b { return a == nil || (b != nil && a! < b!) }
            return $0 < $1
        }
    }
    func newIDs(ids: [String]) -> [String] {
        let evaluated = Set(ordered + (topTen?.backlog ?? []))
        return ids.filter { !evaluated.contains($0) }
    }
    func needsReview(ids: [String]) -> Bool {
        !newIDs(ids: ids).isEmpty || (ordered.count < 10 && !backlogIDs(ids: ids).isEmpty)
    }
    // Compatibility for older callers. Global verification is never a
    // requirement for finishing a screening review.
    func isVerified(ids: [String]) -> Bool {
        guard newIDs(ids: ids).isEmpty, !isActive else { return false }
        let backlog = backlogIDs(ids: ids)
        if backlog.isEmpty { return true }
        guard ordered.count == 10, let threshold = ordered.last else { return false }
        let below = PreferenceGraph(topTen?.preferences ?? []).below(threshold)
        return backlog.allSatisfy(below.contains)
    }
    var isActive: Bool { topTen?.replenishing == true || pair != nil }

    mutating func startSession(ids: [String]) {
        normalize(ids: ids)
        let newIdeas = newIDs(ids: ids)
        if !newIdeas.isEmpty {
            // An explicit Review always checks new arrivals ahead of a paused
            // backlog insertion. Its answered bounds remain in preferences.
            if let candidate = topTen?.candidate, candidate.item != newIdeas.first {
                topTen?.candidate = nil
            }
            screeningReview?.reviewingBacklog = false
        } else if !isActive {
            screeningReview?.reviewingBacklog = true
            let backlog = backlogIDs(ids: ids)
            screeningReview?.backlogRemaining = backlog
            screeningReview?.backlogStarted = []
        }
        topTen?.replenishing = true
        advance(ids: ids, includeNewIdeas: true)
    }
    mutating func replenish(ids: [String]) { startSession(ids: ids) }

    /// Screen one idea against #10, then use binary insertion only if it wins.
    /// A new-idea session ends without automatically starting a backlog pass.
    /// Backlog passes are optional, oldest-review first, and visit each item once.
    mutating func advance(ids: [String], includeNewIdeas: Bool = false) {
        normalize(ids: ids)
        if !includeNewIdeas, pair != nil { return }
        guard includeNewIdeas || isActive else { return }
        if includeNewIdeas, let candidate = topTen?.candidate,
           candidate.screening || candidate.low < candidate.high,
           let newest = newIDs(ids: ids).first, candidate.item != newest {
            // Switch only between questions, never while a choice is visible.
            // Saved bounds are recovered from this candidate's answer edges.
            topTen?.candidate = nil
        }
        while true {
            if topTen?.candidate == nil {
                let item: String
                if let newest = newIDs(ids: ids).first { item = newest }
                else if screeningReview?.reviewingBacklog == true,
                        let oldest = screeningReview?.backlogRemaining.first(where: {
                            ids.contains($0) && !ordered.contains($0)
                        }) {
                    item = oldest
                    if !(screeningReview?.backlogStarted.contains(item) ?? false) {
                        // A fresh backlog review must not silently reuse its
                        // old rejection. Preserve every other idea's order.
                        topTen?.preferences.removeAll { $0.winner == item || $0.loser == item }
                        rememberChain(ordered)
                        screeningReview?.backlogStarted.append(item)
                    }
                } else {
                    topTen?.replenishing = false
                    return
                }
                topTen?.candidate = TopTenInsertion(item: item, base: ordered, high: ordered.count, screening: ordered.count == 10)
            }
            guard let candidate = topTen?.candidate else { return }
            if !candidate.screening, candidate.low == candidate.high {
                finishCandidate(candidate)
                continue
            }
            guard let question = pair else { topTen?.candidate = nil; continue }
            // Reuse answers from a paused insertion or previous app version.
            // Backlog candidates explicitly clear their old evidence above.
            if let winner = PreferenceGraph(topTen?.preferences ?? []).winner(question.first, question.second) {
                resolveCandidate(winner)
            } else { return }
        }
    }

    private mutating func finishCandidate(_ candidate: TopTenInsertion) {
        topTen?.candidate = nil
        topTen?.backlog.removeAll { $0 == candidate.item }
        ordered.insert(candidate.item, at: min(candidate.low, ordered.count))
        if ordered.count > 10 {
            let displaced = ordered.removeLast()
            topTen?.backlog.append(displaced)
        }
        screeningReview?.backlogRemaining.removeAll { $0 == candidate.item }
        rememberChain(ordered)
    }
    private mutating func resolveCandidate(_ preferred: String) {
        guard var candidate = topTen?.candidate, let question = pair else { return }
        if candidate.screening {
            if preferred != candidate.item {
                if !(topTen?.backlog.contains(candidate.item) ?? false) { topTen?.backlog.append(candidate.item) }
                screeningReview?.backlogRemaining.removeAll { $0 == candidate.item }
                topTen?.candidate = nil
                return
            }
            candidate.screening = false
            candidate.high = candidate.base.count - 1
        } else {
            let midpoint = (candidate.low + candidate.high) / 2
            if preferred == question.first { candidate.high = midpoint }
            else { candidate.low = midpoint + 1 }
        }
        topTen?.candidate = candidate
    }
    mutating func apply(_ preferred: String, now: Date = Date()) {
        guard let pair, preferred == pair.first || preferred == pair.second else { return }
        remember(preferred, preferred == pair.first ? pair.second : pair.first)
        screeningReview?.lastReviewed[pair.first] = now
        screeningReview?.lastReviewed[pair.second] = now
        resolveCandidate(preferred)
    }

    mutating func rerank(_ id: String, ids: [String]) {
        normalize(ids: ids)
        ordered.removeAll { $0 == id }
        topTen?.backlog.removeAll { $0 == id }
        topTen?.preferences.removeAll { $0.winner == id || $0.loser == id }
        rememberChain(ordered)
        topTen?.presented?.removeAll { $0 == id }
        topTen?.candidate = TopTenInsertion(item: id, base: ordered, high: ordered.count, screening: ordered.count == 10)
        screeningReview?.reviewingBacklog = false
        topTen?.replenishing = true
        advance(ids: [id] + ids.filter { $0 != id }, includeNewIdeas: true)
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
        let backlogIDs = ranking.backlogIDs(ids: ids)
        let backlog = backlogIDs.compactMap { byID[$0] }
        let review = ranking.needsReview(ids: ids)
        return InboxRankingSnapshot(
            ranked: ranking.ordered.compactMap { byID[$0] },
            unseen: pending.filter { !seen.contains($0.id) },
            inProgress: pending.filter { seen.contains($0.id) },
            backlog: backlog,
            pair: ranking.pair, isActive: ranking.isActive, needsReview: review,
            isVerified: ranking.isVerified(ids: ids),
            oldestBacklogReview: backlog.compactMap { ranking.screeningReview?.lastReviewed[$0.id] }.min(),
            backlogWithoutReviewDateCount: backlog.filter { ranking.screeningReview?.lastReviewed[$0.id] == nil }.count,
            reviewingBacklog: ranking.screeningReview?.reviewingBacklog == true)
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
    public var backlogCaptures: [Capture] { captures(in: rankingProjection.backlogIDs(ids: rankingIDs)) }
    public var rankingPair: RankingPair? { rankingProjection.pair }
    public var rankingIsActive: Bool { rankingProjection.isActive }
    public var needsTopTenReplenishment: Bool { rankingProjection.needsReview(ids: rankingIDs) }
    public var topTenIsVerified: Bool { rankingProjection.isVerified(ids: rankingIDs) }

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
    public mutating func chooseCapture(_ preferred: String, from expected: RankingPair, writer: String, now: Date = Date()) {
        normalizeInboxRanking(writer: writer)
        guard var ranking = inboxRanking, ranking.pair == expected,
              preferred == expected.first || preferred == expected.second else { return }
        ranking.recordPresentation()
        // Save the answer before advancing this candidate or taking the next arrival.
        ranking.apply(preferred, now: now); ranking.advance(ids: rankingIDs, includeNewIdeas: true)
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
