import Foundation

public struct LedgerBackup: Codable, Sendable {
    public var formatVersion = 1
    public var savedAt: Date
    public var ledger: Ledger
    public init(ledger: Ledger, savedAt: Date = Date()) { self.ledger = ledger; self.savedAt = savedAt }
    public func encoded() throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(self) }
    public static func decode(_ data: Data) throws -> LedgerBackup {
        let decoder = JSONDecoder()
        let backup: LedgerBackup
        if let envelope = try? decoder.decode(LedgerBackup.self, from: data) { backup = envelope }
        else { backup = LedgerBackup(ledger: try decoder.decode(Ledger.self, from: data)) }
        guard backup.formatVersion == 1, (1...2).contains(backup.ledger.schemaVersion) else { throw BackupError.unsupported }
        return backup
    }
    public enum BackupError: LocalizedError {
        case unsupported
        public var errorDescription: String? { "This backup requires a newer version of Ledger." }
    }
}
