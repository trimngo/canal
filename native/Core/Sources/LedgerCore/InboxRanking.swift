import Foundation

public struct RankingPair: Equatable, Sendable {
    public var first: String
    public var second: String
}

public struct MergeRanking: Codable, Equatable, Sendable {
    var runs: [[String]]
    var nextRuns: [[String]] = []
    var left: [String] = []
    var right: [String] = []
    var merged: [String] = []

    mutating func advance(valid: Set<String>) -> [String]? {
        runs = runs.map { $0.filter(valid.contains) }.filter { !$0.isEmpty }
        nextRuns = nextRuns.map { $0.filter(valid.contains) }.filter { !$0.isEmpty }
        left = left.filter(valid.contains); right = right.filter(valid.contains); merged = merged.filter(valid.contains)
        while left.isEmpty || right.isEmpty {
            if !merged.isEmpty || !left.isEmpty || !right.isEmpty {
                nextRuns.append(merged + left + right)
                merged = []; left = []; right = []
            }
            if runs.isEmpty {
                if nextRuns.count <= 1 { return nextRuns.first ?? [] }
                runs = nextRuns; nextRuns = []
            }
            left = runs.removeFirst()
            if runs.isEmpty { nextRuns.append(left); left = []; continue }
            right = runs.removeFirst()
        }
        return nil
    }
}

public struct InsertionRanking: Codable, Equatable, Sendable {
    var item: String
    var base: [String]
    var low = 0
    var high: Int
}

public struct InboxRanking: Codable, Equatable, Sendable {
    public var ordered: [String] = []
    public var merge: MergeRanking?
    public var insertion: InsertionRanking?
    public var revision = Revision()
    public init() {}
    public var pair: RankingPair? {
        if let merge, let first = merge.left.first, let second = merge.right.first {
            return RankingPair(first: first, second: second)
        }
        if let insertion, insertion.low < insertion.high {
            return RankingPair(first: insertion.item, second: insertion.base[(insertion.low + insertion.high) / 2])
        }
        return nil
    }

    mutating func prepare(ids: [String]) {
        let valid = Set(ids)
        ordered = ordered.filter(valid.contains)
        if var session = merge {
            if let result = session.advance(valid: valid) { ordered = result; merge = nil }
            else { merge = session; return }
        }
        if var session = insertion {
            guard valid.contains(session.item) else { insertion = nil; prepare(ids: ids); return }
            let base = session.base.filter(valid.contains)
            // A deletion/completion changes the search bounds. Restart just this
            // insertion rather than applying stale comparison indexes.
            if base != session.base { session.base = base; session.low = 0; session.high = base.count }
            if session.low < session.high { insertion = session; return }
            ordered = base
            ordered.insert(session.item, at: min(session.low, base.count))
            insertion = nil
        }
        let pending = ids.filter { !ordered.contains($0) }
        guard !pending.isEmpty else { return }
        if ordered.isEmpty {
            var session = MergeRanking(runs: pending.map { [$0] })
            if let result = session.advance(valid: valid) { ordered = result }
            else { merge = session }
        } else {
            insertion = InsertionRanking(item: pending[0], base: ordered, high: ordered.count)
        }
    }

    mutating func choose(_ preferred: String) {
        guard let pair, preferred == pair.first || preferred == pair.second else { return }
        if var session = merge {
            session.merged.append(preferred == pair.first ? session.left.removeFirst() : session.right.removeFirst())
            merge = session
        } else if var session = insertion {
            let mid = (session.low + session.high) / 2
            if preferred == pair.first { session.high = mid } else { session.low = mid + 1 }
            insertion = session
        }
    }
}

extension Ledger {
    public var activeCaptures: [Capture] { captures.filter { $0.deletedAt == nil && !$0.isDone } }
    public var rankedCaptureIDs: [String] {
        let valid = Set(activeCaptures.map(\.id))
        return (inboxRanking?.ordered ?? []).filter(valid.contains)
    }
    public var rankedCaptures: [Capture] {
        let byID = Dictionary(activeCaptures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return rankedCaptureIDs.compactMap { byID[$0] }
    }
    public var unrankedCaptures: [Capture] {
        let ranked = Set(rankedCaptureIDs)
        return activeCaptures.filter { !ranked.contains($0.id) }.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }
    }
    public var rankingPair: RankingPair? { inboxRanking?.pair }

    public mutating func prepareRanking(writer: String) {
        var ranking = inboxRanking ?? InboxRanking()
        let previous = ranking
        ranking.prepare(ids: activeCaptures.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }.map(\.id))
        guard ranking != previous else { return }
        ranking.revision = nextRevision(writer: writer); inboxRanking = ranking
    }

    public mutating func chooseCapture(_ preferred: String, from expected: RankingPair, writer: String) {
        prepareRanking(writer: writer)
        guard var ranking = inboxRanking, ranking.pair == expected else { return }
        ranking.choose(preferred)
        ranking.revision = nextRevision(writer: writer); inboxRanking = ranking
        prepareRanking(writer: writer)
    }

    public mutating func rerankCapture(_ id: String, writer: String) {
        guard activeCaptures.contains(where: { $0.id == id }) else { return }
        var ranking = inboxRanking ?? InboxRanking()
        ranking.ordered.removeAll { $0 == id }
        ranking.merge = nil; ranking.insertion = nil
        ranking.revision = nextRevision(writer: writer); inboxRanking = ranking
        prepareRanking(writer: writer)
    }

    public mutating func setCaptureDeleted(_ id: String, deleted: Bool, writer: String, now: Date = Date()) {
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        let revision = nextRevision(writer: writer)
        captures[index].deletedAt = deleted ? now : nil
        captures[index].revision = revision
    }
}
