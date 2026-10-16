import Foundation
import Combine
import LedgerCore

@MainActor
final class LedgerStore: ObservableObject {
    static let shared = LedgerStore()
    @Published private(set) var ledger = Ledger()
    @Published var sampleRequestID = UUID()
    @Published var pendingLogRequest = false
    @Published var quickReplyDraft: String?
    @Published var error: String?
    @Published var syncStatus = "Saved on this device"
    @Published var companionStatus = "Connecting to paired device…"
    @Published var companionDiagnostic: String?
    @Published var backupStatus = "Automatic backup starts on iPhone"
    @Published private(set) var canUndoLogDeletion = false
    private var logDeletion: LogDeletion?
    private var logUndoExpiry: Task<Void, Never>?
    @Published private(set) var canUndoCaptureDeletion = false
    private var captureDeletion: Capture?
    #if os(iOS)
    private(set) var backup: AutomaticBackup?
    #endif
    @Published private(set) var storageAvailable = true
    @Published private(set) var canUndoGrouping = false
    private var groupingUndo: [(before: CheckIn, after: CheckIn)] = []
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
            if ProcessInfo.processInfo.arguments.contains("--ui-empty-ledger") {
                try JSONEncoder().encode(Ledger()).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-legacy-ledger") {
                var fixture = Ledger(); fixture.schemaVersion = 1
                fixture.entries = [CheckIn(end: Ledger.slotEnd(at: Date()), activity: "Legacy sample UI fixture", categoryID: "work", revision: Revision(counter: 1, writer: "fixture"))]
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-grouping-ledger") {
                var fixture = Ledger()
                let now = Date()
                try fixture.saveSample(at: now.addingTimeInterval(-3600), activity: "Preparing classes", categoryID: "work", writer: "fixture", now: now)
                try fixture.saveSample(at: now.addingTimeInterval(-1800), activity: "Quokka activity fixture", categoryID: nil, writer: "fixture", now: now)
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-group-history") {
                var fixture = Ledger()
                try fixture.saveSample(id: "older", at: Date().addingTimeInterval(-10 * 86400), activity: "Older work observation", categoryID: "work", writer: "fixture")
                try fixture.saveSample(id: "recent", at: Date().addingTimeInterval(-60), activity: "Recent work observation", categoryID: "work", writer: "fixture")
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-inbox-fixture") {
                var fixture = Ledger()
                for (i, item) in [("c", "Third idea"), ("a", "First idea"), ("b", "Second idea")].enumerated() {
                    try fixture.addCapture(text: item.1, id: item.0, writer: "fixture", now: Date().addingTimeInterval(Double(i - 10)))
                }
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-inbox-export-fixture") {
                var fixture = Ledger()
                try fixture.addCapture(text: "Idea to analyze\nKeep every line", id: "open", writer: "fixture")
                try fixture.addCapture(text: "Completed idea", id: "done", writer: "fixture")
                try fixture.addCapture(text: "Deleted idea", id: "removed", writer: "fixture")
                fixture.setCaptureDone(id: "done", done: true, writer: "fixture")
                fixture.setCaptureDeleted("removed", deleted: true, writer: "fixture")
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-backup-fixture") {
                var fixture = Ledger()
                let earlier = Date().addingTimeInterval(-2 * 86400)
                try fixture.saveSample(at: earlier.addingTimeInterval(-3600), activity: "Restored older activity", categoryID: "work", writer: "fixture")
                try fixture.saveSample(at: earlier, activity: "Restored second activity", categoryID: "work", writer: "fixture")
                let backups = directory.appendingPathComponent("UITestBackups")
                try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
                let url = backups.appendingPathComponent("restore-fixture.json")
                try LedgerBackup(ledger: fixture).encoded().write(to: url, options: [.atomic])
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-corrupt-ledger") {
                try Data("Unrecoverable UI fixture bytes".utf8).write(to: file, options: [.atomic])
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
        #if os(iOS)
        if backup == nil { backup = AutomaticBackup(store: self, writer: writer) }
        #endif
        guard storageAvailable else { backupStatus = "Backup paused · restore your saved data to resume"; return }
        guard !started else { return }; started = true
        do {
            var draft = ledger
            draft.ensureDefaultGroups(writer: writer)
            draft.prepareGroupSuggestions(writer: writer)
            if draft != ledger {
                let backup = file.deletingLastPathComponent().appendingPathComponent("ledger-before-confirmed-grouping.json")
                if FileManager.default.fileExists(atPath: file.path), !FileManager.default.fileExists(atPath: backup.path) {
                    try Data(contentsOf: file).write(to: backup, options: [.atomic])
                }
                try commit(draft)
            }
        } catch { report(error) }
        companion = CompanionSync(store: self)
        let cloudFlag = Bundle.main.object(forInfoDictionaryKey: "LedgerCloudEnabled")
        if cloudFlag as? Bool == true || (cloudFlag as? String)?.uppercased() == "YES" {
            cloud = CloudSync(store: self)
        } else { syncStatus = "Saved on this device" }
        saveObserver = { [weak self] in
            // Leave the editor's save transaction before starting device sync.
            Task { @MainActor [weak self] in
                self?.companion?.send()
                self?.cloud?.requestSync()
                #if os(iOS)
                if let self { self.backup?.request(self.ledger) }
                if let self {
                    do { try await NotificationScheduler.shared.apply(self.ledger.settings) } catch { self.report(error) }
                }
                #endif
            }
        }
        importSiriCaptures()
        companion?.start(); cloud?.requestSync()
        #if os(iOS)
        if storageAvailable { backup?.request(ledger) }
        #endif
    }

    func refresh() {
        start(); importSiriCaptures(); companion?.refresh(); cloud?.requestSync()
        #if os(iOS)
        if storageAvailable { backup?.request(ledger) }
        #endif
    }

    private func importSiriCaptures() {
        #if os(watchOS)
        do {
            let pending = try SiriCaptureQueue.pending()
            guard !pending.isEmpty else { return }
            var draft = ledger
            for entry in pending { try draft.saveQuickCapture(entry, writer: writer) }
            if draft != ledger { try commit(draft) }
            // Delete only after an atomic ledger commit. A crash before removal
            // safely replays the queue without duplicating/reopening a capture.
            for entry in pending { try SiriCaptureQueue.remove(entry) }
        } catch { report(error) }
        #endif
    }

    private func commit(_ draft: Ledger) throws {
        guard storageAvailable else { throw StoreError.unavailable }
        try JSONEncoder().encode(draft).write(to: file, options: [.atomic])
        ledger = draft
        saveObserver?()
    }

    func merge(_ incoming: Ledger) throws {
        guard (1...2).contains(incoming.schemaVersion) else { throw StoreError.unsupportedVersion }
        var draft = ledger; draft.merge(incoming)
        draft.prepareGroupSuggestions(writer: writer)
        if draft != ledger { try commit(draft) }
    }

    func beginSample() { pendingLogRequest = true; sampleRequestID = UUID() }

    func saveSample(id: String? = nil, at timestamp: Date = Date(), activity: String, categoryID: String?) throws {
        var draft = ledger
        try draft.saveSample(id: id, at: timestamp, activity: activity, categoryID: categoryID, writer: writer)
        try commit(draft)
    }

    func deleteLog(_ entry: CheckIn) throws {
        guard !ledger.isLogDeleted(entry.id) else { return }
        var draft = ledger; draft.setLogDeleted(entry.id, deleted: true, writer: writer)
        try commit(draft)
        logDeletion = draft.logDeletions?.first { $0.id == entry.id }; canUndoLogDeletion = true
        logUndoExpiry?.cancel()
        logUndoExpiry = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            self?.canUndoLogDeletion = false; self?.logDeletion = nil
        }
    }
    func undoLogDeletion() {
        do {
            guard let record = logDeletion,
                  ledger.logDeletions?.first(where: { $0.id == record.id }) == record else {
                canUndoLogDeletion = false; return
            }
            var draft = ledger; draft.setLogDeleted(record.id, deleted: false, writer: writer)
            try commit(draft)
            logUndoExpiry?.cancel(); logDeletion = nil; canUndoLogDeletion = false
        } catch { report(error) }
    }

    func saveQuickSample(_ text: String, id: String = UUID().uuidString, at timestamp: Date = Date()) throws {
        start()
        var draft = ledger
        try draft.saveQuickSample(id: id, at: timestamp, activity: text, writer: writer)
        if draft != ledger { try commit(draft) }
    }

    func saveSiriEntry(_ entry: QuickCaptureEntry) throws {
        start()
        var draft = ledger; try draft.saveQuickCapture(entry, writer: writer)
        if draft != ledger { try commit(draft) }
    }

    @discardableResult
    func addCapture(_ text: String, at timestamp: Date = Date()) throws -> Capture {
        var draft = ledger
        let capture = try draft.addCapture(text: text, writer: writer, now: timestamp)
        try commit(draft)
        return capture
    }

    func setCaptureDone(_ capture: Capture, done: Bool) throws {
        var draft = ledger; draft.setCaptureDone(id: capture.id, done: done, writer: writer); try commit(draft)
    }

    func deleteCapture(_ capture: Capture) throws {
        var draft = ledger; draft.setCaptureDeleted(capture.id, deleted: true, writer: writer); draft.prepareRanking(writer: writer)
        try commit(draft)
        captureDeletion = draft.captures.first { $0.id == capture.id }; canUndoCaptureDeletion = true
    }

    func undoCaptureDeletion() {
        do {
            guard let deleted = captureDeletion,
                  ledger.captures.first(where: { $0.id == deleted.id })?.revision == deleted.revision else {
                canUndoCaptureDeletion = false; return
            }
            var draft = ledger; draft.setCaptureDeleted(deleted.id, deleted: false, writer: writer); draft.prepareRanking(writer: writer)
            try commit(draft); captureDeletion = nil; canUndoCaptureDeletion = false
        } catch { report(error) }
    }

    func prepareRanking() throws { var draft = ledger; draft.prepareRanking(writer: writer); if draft != ledger { try commit(draft) } }
    func chooseCapture(_ preferred: String, pair: RankingPair) throws {
        var draft = ledger; draft.chooseCapture(preferred, from: pair, writer: writer); try commit(draft)
    }
    func rerankCapture(_ id: String) throws { var draft = ledger; draft.rerankCapture(id, writer: writer); try commit(draft) }

    func restoreBackup(_ data: Data) throws {
        let saved = try LedgerBackup.decode(data)
        let recovery = file.deletingLastPathComponent().appendingPathComponent("ledger-before-restore-\(UUID().uuidString).json")
        if FileManager.default.fileExists(atPath: file.path) { try Data(contentsOf: file).write(to: recovery, options: [.atomic]) }
        var draft = ledger; draft.merge(saved.ledger); draft.prepareGroupSuggestions(writer: writer)
        // An explicitly selected backup can recover an unreadable ledger while
        // retaining its original bytes in a separate recovery file.
        try JSONEncoder().encode(draft).write(to: file, options: [.atomic])
        ledger = draft; storageAvailable = true; error = nil
        start(); refresh()
    }

    func saveCategory(id: String?, name: String) throws {
        var draft = ledger; try draft.saveCategory(id: id, name: name, writer: writer); try commit(draft)
    }

    func deleteCategory(id: String) throws {
        var draft = ledger; try draft.deleteCategory(id: id, writer: writer); try commit(draft)
        groupingUndo = []; canUndoGrouping = false
    }

    func categorize(_ entry: CheckIn, categoryID: String?, newGroupName: String? = nil, includeMatching: Bool = false) throws {
        var draft = ledger
        var destination = categoryID
        if let newGroupName {
            try draft.saveCategory(id: nil, name: newGroupName, writer: writer)
            destination = draft.categories.last?.id
        }
        guard let current = draft.entries.first(where: { $0.id == entry.id }) else { return }
        try draft.confirmCategory(for: current.id, categoryID: destination, includeMatching: includeMatching, writer: writer)
        let changed = draft.entries.compactMap { updated -> (before: CheckIn, after: CheckIn)? in
            guard let original = ledger.entries.first(where: { $0.id == updated.id }),
                  original.categoryID != updated.categoryID || original.categoryAssignment != updated.categoryAssignment else { return nil }
            return (original, updated)
        }
        try commit(draft)
        groupingUndo = changed; canUndoGrouping = !changed.isEmpty
    }

    func undoCategorization() {
        do {
            var draft = ledger
            for change in groupingUndo {
                guard let index = draft.entries.firstIndex(where: { $0.id == change.after.id }),
                      draft.entries[index].revision == change.after.revision else { continue }
                let revision = draft.nextRevision(writer: writer)
                draft.entries[index].categoryID = change.before.categoryID
                draft.entries[index].categoryAssignment = change.before.categoryAssignment
                draft.entries[index].revision = revision
            }
            draft.prepareGroupSuggestions(writer: writer)
            try commit(draft)
            groupingUndo = []; canUndoGrouping = false
        } catch { report(error) }
    }

    func saveSettings(_ settings: Settings) throws {
        var draft = ledger; try draft.saveSettings(settings, writer: writer); try commit(draft)
    }

    func categoryName(_ id: String?) -> String { ledger.categories.first { $0.id == id }?.name ?? "Uncategorized" }
    func notificationSummary(now: Date = Date()) -> String {
        let rows = ledger.breakdown(on: now, now: now).filter { $0.minutes > 0 }.sorted { $0.minutes > $1.minutes }
        guard !rows.isEmpty else { return "Log an activity to start today’s breakdown." }
        let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = ledger.settings.use24HourTime ? "MMM d, HH:mm" : "MMM d, h:mm a"
        return "Summary as of \(stamp.string(from: now))\n" + rows.map { "\($0.name): \(Int($0.percent.rounded()))% · \(duration($0.minutes))" }.joined(separator: "\n")
    }
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
        case .unsupportedVersion: return "This data needs a newer version of Dash."
        }
    }
}
