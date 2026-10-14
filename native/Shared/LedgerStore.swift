import Foundation
import Combine
import LedgerCore

@MainActor
final class LedgerStore: ObservableObject {
    static let shared = LedgerStore()
    @Published private(set) var ledger = Ledger()
    @Published var sampleRequestID = UUID()
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
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-legacy-ledger") {
                var fixture = Ledger(); fixture.schemaVersion = 1
                fixture.entries = [CheckIn(end: Ledger.slotEnd(at: Date()), activity: "Legacy sample UI fixture", categoryID: "work", revision: Revision(counter: 1, writer: "fixture"))]
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            #endif
            if FileManager.default.fileExists(atPath: file.path) {
                let original = try Data(contentsOf: file)
                var loaded = try JSONDecoder().decode(Ledger.self, from: original)
                guard (1...2).contains(loaded.schemaVersion) else { throw StoreError.unsupportedVersion }
                if loaded.schemaVersion == 1 {
                    let backup = directory.appendingPathComponent("ledger-before-instant-samples.json")
                    if !FileManager.default.fileExists(atPath: backup.path) { try original.write(to: backup, options: [.atomic]) }
                    loaded.schemaVersion = 2
                    try JSONEncoder().encode(loaded).write(to: file, options: [.atomic])
                }
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
            // Leave the editor's save transaction before starting device sync.
            Task { @MainActor [weak self] in
                self?.companion?.send()
                self?.cloud?.requestSync()
            }
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
        guard (1...2).contains(incoming.schemaVersion) else { throw StoreError.unsupportedVersion }
        var draft = ledger; draft.merge(incoming)
        if draft != ledger { try commit(draft) }
    }

    func beginSample() { sampleRequestID = UUID() }

    func saveSample(id: String? = nil, at timestamp: Date = Date(), activity: String, categoryID: String?) throws {
        var draft = ledger
        try draft.saveSample(id: id, at: timestamp, activity: activity, categoryID: categoryID, writer: writer)
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

    func categoryName(_ id: String?) -> String { ledger.categories.first { $0.id == id }?.name ?? "Uncategorized" }
    func time(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = ledger.settings.use24HourTime ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
    func duration(_ minutes: Double) -> String {
        if minutes > 0, minutes < 1 { return "<1m" }
        let whole = Int(minutes.rounded())
        return whole < 60 ? "\(whole)m" : "\(whole / 60)h \(whole % 60)m"
    }
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
