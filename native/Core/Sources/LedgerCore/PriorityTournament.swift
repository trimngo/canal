import Foundation

/// Legacy persisted tournament payload. Retained only so old cloud records and
/// backups decode. InboxRanking migrates its shortlist and saved preferences to
/// screening; the tournament algorithm is no longer part of the review flow.
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
    }

}
