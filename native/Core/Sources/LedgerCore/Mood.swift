import Foundation

public enum MoodError: LocalizedError {
    case invalidValue
    public var errorDescription: String? { "Choose a mood from 1 (low) to 5 (high), or leave it blank." }
}

extension Ledger {
    public mutating func setMood(for id: String, value: Int?, writer: String) throws {
        guard value == nil || (1...5).contains(value!) else { throw MoodError.invalidValue }
        guard !isLogDeleted(id) else { throw LedgerError.deletedSample }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw LedgerError.invalidSlot }
        guard entries[index].mood != value else { return }
        entries[index].mood = value
        entries[index].revision = nextRevision(writer: writer)
    }
}
