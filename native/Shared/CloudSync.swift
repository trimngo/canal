import Foundation
import CloudKit
import LedgerCore

private enum CloudItem: Codable {
    case category(LedgerCategory), entry(CheckIn), capture(Capture), settings(Settings)
    var id: String {
        switch self {
        case .category(let item): return "category-\(item.id)"
        case .entry(let item): return "entry-\(item.id)"
        case .capture(let item): return "capture-\(item.id)"
        case .settings: return "settings"
        }
    }
    var revision: Revision {
        switch self {
        case .category(let item): return item.revision
        case .entry(let item): return item.revision
        case .capture(let item): return item.revision
        case .settings(let item): return item.revision
        }
    }
    func apply(to ledger: inout Ledger) {
        var remote = Ledger(); remote.categories = []; remote.entries = []; remote.captures = []
        switch self {
        case .category(let item): remote.categories = [item]
        case .entry(let item): remote.entries = [item]
        case .capture(let item): remote.captures = [item]
        case .settings(let item): remote.settings = item
        }
        ledger.merge(remote)
    }
    static func all(in ledger: Ledger) -> [CloudItem] {
        ledger.categories.map(CloudItem.category) + ledger.entries.map(CloudItem.entry) + ledger.captures.map(CloudItem.capture) + [.settings(ledger.settings)]
    }
}

@MainActor
final class CloudSync {
    private weak var store: LedgerStore?
    private let container: CKContainer
    private var task: Task<Void, Never>?
    private var requested = false
    init(store: LedgerStore) {
        self.store = store
        let name = Bundle.main.object(forInfoDictionaryKey: "LedgerCloudContainer") as? String ?? "iCloud.com.trimngo.TimeLedger"
        container = CKContainer(identifier: name)
    }

    func requestSync() {
        requested = true
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            // Debounce keyboard edits and Watch merges.
            try? await Task.sleep(nanoseconds: 500_000_000)
            while self.requested {
                self.requested = false
                do { try await self.sync() }
                catch {
                    self.store?.syncStatus = "Saved locally · iCloud sync waiting"
                    self.requested = false
                    break // Retry on the next change or foreground, never discard local data.
                }
            }
            self.task = nil
        }
    }

    private func sync() async throws {
        guard let store else { return }
        guard try await container.accountStatus() == .available else { throw CKError(.notAuthenticated) }
        store.syncStatus = "Syncing with iCloud…"
        let database = container.privateCloudDatabase
        var records: [String: CKRecord] = [:]
        var remote = Ledger(); remote.categories = []; remote.entries = []; remote.captures = []
        var page = try await database.records(matching: CKQuery(recordType: "LedgerItem", predicate: NSPredicate(value: true)))
        while true {
            for (_, result) in page.matchResults {
                let record = try result.get()
                guard let data = record["payload"] as? Data else { continue }
                let item = try JSONDecoder().decode(CloudItem.self, from: data)
                records[item.id] = record; item.apply(to: &remote)
            }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor)
        }
        try store.merge(remote)
        let items = CloudItem.all(in: store.ledger)
        for item in items {
            var record = records[item.id] ?? CKRecord(recordType: "LedgerItem", recordID: CKRecord.ID(recordName: item.id))
            if let data = record["payload"] as? Data,
               try JSONDecoder().decode(CloudItem.self, from: data).revision >= item.revision { continue }
            record["payload"] = try JSONEncoder().encode(item) as CKRecordValue
            do { _ = try await database.save(record) }
            catch let error as CKError where error.code == .serverRecordChanged {
                // A concurrent device won the race. Merge its version before retrying;
                // never blindly overwrite a newer cloud value.
                guard let server = error.serverRecord, let data = server["payload"] as? Data else { throw error }
                let serverItem = try JSONDecoder().decode(CloudItem.self, from: data)
                var merged = store.ledger; serverItem.apply(to: &merged); try store.merge(merged)
                if serverItem.revision < item.revision {
                    record = server; record["payload"] = try JSONEncoder().encode(item) as CKRecordValue
                    _ = try await database.save(record)
                }
            }
        }
        store.syncStatus = "Synced with private iCloud"
    }
}
