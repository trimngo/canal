import Foundation
import Combine
import LedgerCore

@MainActor
final class LedgerStore: ObservableObject {
    static let shared = LedgerStore()
    @Published private(set) var ledger = Ledger()
    @Published var selectedSlot = Ledger.slotEnd(at: Date())
    @Published var error: String?
    @Published var syncStatus = "Saved on this device"
    @Published private(set) var storageAvailable = true
    private let file: URL
    private let writer: String
    private var saveObserver: (() -> Void)?
    private(set) var cloud: CloudSync?
    private(set) var companion: CompanionSync?
    private var started = false

    private init() {
        let defaults = UserDefaults.standard
        writer = defaults.string(forKey: "ledger.writer") ?? UUID().uuidString
        defaults.set(writer, forKey: "ledger.writer")
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = directory.appendingPathComponent("ledger-v1.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let loaded = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file))
                guard loaded.schemaVersion == 1 else { throw StoreError.unsupportedVersion }
                ledger = loaded
            }
        } catch {
            // Never replace unreadable user data with an empty ledger.
            storageAvailable = false
            self.error = "Could not open saved data. Your original file has been preserved. \(error.localizedDescription)"
        }
    }

    func start() {
        guard !started, storageAvailable else { return }; started = true
        companion = CompanionSync(store: self)
        let cloudFlag = Bundle.main.object(forInfoDictionaryKey: "LedgerCloudEnabled")
        if cloudFlag as? Bool == true || (cloudFlag as? String)?.uppercased() == "YES" {
            cloud = CloudSync(store: self)
        } else { syncStatus = "Device + paired Watch · iCloud setup pending" }
        saveObserver = { [weak self] in
            self?.companion?.send()
            self?.cloud?.requestSync()
        }
        companion?.start(); cloud?.requestSync()
    }

    func refresh() { start(); companion?.send(); cloud?.requestSync() }

    private func commit(_ draft: Ledger) throws {
        guard storageAvailable else { throw StoreError.unavailable }
        try JSONEncoder().encode(draft).write(to: file, options: [.atomic])
        ledger = draft
        saveObserver?()
    }

    func merge(_ incoming: Ledger) throws {
        guard incoming.schemaVersion == 1 else { throw StoreError.unsupportedVersion }
        var draft = ledger; draft.merge(incoming)
        if draft != ledger { try commit(draft) }
    }

    func saveCheckIn(end: Date, activity: String, categoryID: String?) throws {
        var draft = ledger
        try draft.saveCheckIn(end: end, activity: activity, categoryID: categoryID, writer: writer)
        try commit(draft)
    }

    func addCapture(_ text: String) throws {
        var draft = ledger; try draft.addCapture(text: text, writer: writer); try commit(draft)
    }

    func setCaptureDone(_ capture: Capture, done: Bool) throws {
        var draft = ledger; draft.setCaptureDone(id: capture.id, done: done, writer: writer); try commit(draft)
    }

    func saveCategory(id: String?, name: String) throws {
        var draft = ledger; try draft.saveCategory(id: id, name: name, writer: writer); try commit(draft)
    }

    func saveSettings(_ settings: Settings) throws {
        var draft = ledger; try draft.saveSettings(settings, writer: writer); try commit(draft)
    }

    func entry(at end: Date) -> CheckIn? { ledger.entries.first { $0.end == end } }
    func categoryName(_ id: String?) -> String { ledger.categories.first { $0.id == id }?.name ?? "Uncategorized" }
    func time(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = ledger.settings.use24HourTime ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
    func interval(_ end: Date) -> String { "\(time(end.addingTimeInterval(-900)))–\(time(end))" }
    func report(_ error: Error) { self.error = error.localizedDescription }
}

enum StoreError: LocalizedError {
    case unavailable, unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Saved data is unavailable; changes have not been written."
        case .unsupportedVersion: return "This data needs a newer version of Time Ledger."
        }
    }
}
