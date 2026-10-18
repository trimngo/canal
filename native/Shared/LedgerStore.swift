import Foundation
import Combine
import LedgerCore

@MainActor
final class LedgerStore: ObservableObject {
    static let shared = LedgerStore()
    @Published private(set) var ledger = Ledger() { didSet { inboxCache = nil } }
    private var inboxCache: (snapshot: InboxRankingSnapshot, nextReturn: Date?)?
    var inbox: InboxRankingSnapshot {
        if let cached = inboxCache, cached.nextReturn.map({ $0 > Date() }) ?? true { return cached.snapshot }
        let snapshot = ledger.inboxSnapshot
        inboxCache = (snapshot, ledger.snoozedCaptures.first?.snoozedUntil)
        return snapshot
    }
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
            if ProcessInfo.processInfo.arguments.contains("--ui-allocation-fixture") || ProcessInfo.processInfo.arguments.contains("--ui-commitments-fixture") {
                var fixture = Ledger(); fixture.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"), LedgerCategory(id: "music", name: "Music")]
                fixture.settings.wakeUpMinute = 0; fixture.settings.bedtimeMinute = 1439
                try fixture.moveCategory("teaching", to: "work", writer: "fixture")
                let now = Date(), cal = Calendar.current
                let first = cal.startOfDay(for: now).addingTimeInterval(60)
                try fixture.saveSample(id: "today-teaching", at: min(first, now), activity: "Preparing classes", categoryIDs: ["teaching"], writer: "fixture", now: now)
                try fixture.saveSample(id: "today-music", at: now.addingTimeInterval(-1), activity: "Guitar practice", categoryIDs: ["music"], writer: "fixture", now: now)
                if let yesterday = cal.date(byAdding: .day, value: -1, to: first) {
                    try fixture.saveSample(at: yesterday, activity: "Yesterday work", categoryIDs: ["work"], writer: "fixture", now: now)
                }
                try fixture.saveTargets(["work": 30, "music": 15], effectiveAt: now.addingTimeInterval(-60), writer: "fixture")
                if ProcessInfo.processInfo.arguments.contains("--ui-commitments-fixture") {
                    try fixture.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 60, writer: "fixture")
                    try fixture.saveWeeklyCommitment(categoryID: "music", minimumMinutes: 600, writer: "fixture")
                }
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-inbox-fixture") {
                var fixture = Ledger()
                for (i, item) in [("c", "Third idea"), ("a", "First idea"), ("b", "Second idea")].enumerated() {
                    try fixture.addCapture(text: item.1, id: item.0, writer: "fixture", now: Date().addingTimeInterval(Double(i - 10)))
                }
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-ranked-inbox-fixture") {
                var fixture = Ledger(), ranked = InboxRanking()
                for index in 1...14 {
                    let id = "ranked-\(index)"
                    try fixture.addCapture(text: "Ranked priority \(index)", id: id, writer: "fixture", now: Date().addingTimeInterval(Double(-index * 60)))
                    ranked.ordered.append(id)
                }
                ranked.revision = fixture.nextRevision(writer: "fixture"); fixture.inboxRanking = ranked
                fixture.importReminders([
                    ReminderSnapshot(identifiers: ["new-import"], title: "New imported idea", createdAt: Date()),
                    ReminderSnapshot(identifiers: ["older-import"], title: "Older imported idea", createdAt: Date().addingTimeInterval(-120))
                ], writer: "fixture")
                try fixture.addCapture(text: "New manual idea", id: "new-manual", writer: "fixture")
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-tournament-fixture") {
                var fixture = Ledger(), ranking = InboxRanking()
                for index in 1...26 {
                    let id = "priority-\(index)"
                    try fixture.addCapture(text: "Priority \(index)", id: id, writer: "fixture", now: Date().addingTimeInterval(Double(index - 60)))
                    if index <= 10 { ranking.ordered.append(id) }
                }
                ranking.revision = fixture.nextRevision(writer: "fixture"); fixture.inboxRanking = ranking
                fixture.prepareRanking(writer: "fixture")
                while let pair = fixture.rankingPair {
                    // All incoming ideas are initially below the known ten.
                    fixture.chooseCapture(pair.second, from: pair, writer: "fixture")
                }
                fixture.setCaptureDone(id: "priority-1", done: true, writer: "fixture")
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
                if let ranking = loaded.inboxRanking, ranking.topTen == nil {
                    let recovery = directory.appendingPathComponent("ledger-before-top-ten.json")
                    if !FileManager.default.fileExists(atPath: recovery.path) { try original.write(to: recovery, options: [.atomic]) }
                }
                if let ranking = loaded.inboxRanking, ranking.priorityTournament == nil {
                    let recovery = directory.appendingPathComponent("ledger-before-priority-tournament.json")
                    if !FileManager.default.fileExists(atPath: recovery.path) { try original.write(to: recovery, options: [.atomic]) }
                }
                if loaded.schemaVersion == 1 {
                    let backup = directory.appendingPathComponent("ledger-before-instant-samples.json")
                    if !FileManager.default.fileExists(atPath: backup.path) { try original.write(to: backup, options: [.atomic]) }
                    loaded.schemaVersion = 2
                    try JSONEncoder().encode(loaded).write(to: file, options: [.atomic])
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") }) {
                    loaded.settings.wakeUpMinute = 0; loaded.settings.bedtimeMinute = 1439
                    try JSONEncoder().encode(loaded).write(to: file, options: [.atomic])
                }
                #endif
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
            if draft.settings.wakingTimeZoneIdentifier == nil {
                var settings = draft.settings; settings.wakingTimeZoneIdentifier = TimeZone.current.identifier
                try draft.saveSettings(settings, writer: writer)
            }
            draft.ensureDefaultGroups(writer: writer)
            draft.prepareGroupSuggestions(writer: writer)
            draft.normalizeInboxRanking(writer: writer)
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
        do { try resumeRanking() } catch { report(error) }
        #if os(iOS)
        if storageAvailable { backup?.request(ledger) }
        #endif
    }

    func pairedDeviceReceivedSample(_ id: String) -> Bool {
        guard let entry = ledger.entries.first(where: { $0.id == id }) else { return false }
        return companion?.hasReceivedSample(entry) == true
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

    private func commit(_ value: Ledger) throws {
        guard storageAvailable else { throw StoreError.unavailable }
        var draft = value
        draft.normalizeInboxRanking(writer: writer)
        try JSONEncoder().encode(draft).write(to: file, options: [.atomic])
        ledger = draft
        saveObserver?()
    }

    func merge(_ incoming: Ledger) throws {
        guard (1...2).contains(incoming.schemaVersion) else { throw StoreError.unsupportedVersion }
        var draft = ledger; draft.merge(incoming)
        draft.normalizeInboxRanking(writer: writer)
        draft.prepareGroupSuggestions(writer: writer)
        if draft != ledger { try commit(draft) }
    }

    func beginSample() { pendingLogRequest = true; sampleRequestID = UUID() }

    func saveSample(id: String? = nil, at timestamp: Date = Date(), activity: String, categoryID: String?) throws {
        var draft = ledger
        try draft.saveSample(id: id, at: timestamp, activity: activity, categoryID: categoryID, writer: writer)
        try commit(draft)
    }

    func saveSample(id: String? = nil, at timestamp: Date = Date(), activity: String, categoryIDs: [String]) throws {
        var draft = ledger
        try draft.saveSample(id: id, at: timestamp, activity: activity, categoryIDs: categoryIDs, writer: writer)
        try commit(draft)
    }
    func saveTargets(_ values: [String: Double]) throws {
        var draft = ledger; try draft.saveTargets(values, writer: writer); try commit(draft)
    }
    func saveWeeklyCommitment(categoryID: String, minimumMinutes: Int?) throws {
        var draft = ledger; try draft.saveWeeklyCommitment(categoryID: categoryID, minimumMinutes: minimumMinutes, writer: writer); try commit(draft)
    }
    func moveCategory(_ id: String, to parent: String?) throws {
        var draft = ledger; try draft.moveCategory(id, to: parent, writer: writer); try commit(draft)
    }
    func reorderCategories(_ ids: [String], parent: String?) throws {
        var draft = ledger; try draft.reorderCategories(ids, parent: parent, writer: writer); try commit(draft)
    }
    func saveWakingOverride(on day: Date, wake: Int, bed: Int, reset: Bool = false) throws {
        var draft = ledger; try draft.saveWakingOverride(on: day, wake: wake, bed: bed, reset: reset, writer: writer); try commit(draft)
    }
    func categoryNames(for entry: CheckIn) -> String {
        let names = ledger.confirmedCategoryIDs(for: entry).map { ledger.categoryPath($0) }
        return names.isEmpty ? "Uncategorized" : names.joined(separator: " + ")
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
    func importReminders(_ snapshots: [ReminderSnapshot]) throws -> Int {
        start()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-reminders-save-failure") { throw StoreError.unavailable }
        #endif
        var draft = ledger
        let count = draft.importReminders(snapshots, writer: writer)
        // Confirm a durable save even on a deletion retry for an existing import.
        // The caller must never remove its source after a failed disk write.
        if draft != ledger || !snapshots.isEmpty { try commit(draft) }
        return count
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

    func updateCaptureText(_ capture: Capture, text: String) throws {
        var draft = ledger; try draft.updateCaptureText(id: capture.id, text: text, writer: writer); try commit(draft)
    }

    func updateCapture(_ capture: Capture, text: String, notes: String) throws {
        var draft = ledger; try draft.updateCapture(id: capture.id, text: text, notes: notes, writer: writer); try commit(draft)
    }

    func snoozeCapture(_ capture: Capture, until: Date) throws {
        var draft = ledger; draft.snoozeCapture(capture.id, until: until, writer: writer); try commit(draft)
    }

    func bringBackCapture(_ capture: Capture) throws {
        var draft = ledger; draft.bringBackCapture(capture.id, writer: writer); try commit(draft)
    }

    func setCaptureReference(_ capture: Capture, reference: Bool) throws {
        var draft = ledger; draft.setCaptureReference(capture.id, reference: reference, writer: writer); try commit(draft)
    }

    func deleteCapture(_ capture: Capture) throws {
        var draft = ledger; draft.setCaptureDeleted(capture.id, deleted: true, writer: writer)
        try commit(draft)
        captureDeletion = draft.captures.first { $0.id == capture.id }; canUndoCaptureDeletion = true
    }

    func undoCaptureDeletion() {
        do {
            guard let deleted = captureDeletion,
                  ledger.captures.first(where: { $0.id == deleted.id })?.revision == deleted.revision else {
                canUndoCaptureDeletion = false; return
            }
            var draft = ledger; draft.setCaptureDeleted(deleted.id, deleted: false, writer: writer)
            try commit(draft); captureDeletion = nil; canUndoCaptureDeletion = false
        } catch { report(error) }
    }

    func prepareRanking() throws { var draft = ledger; draft.prepareRanking(writer: writer); if draft != ledger { try commit(draft) } }
    func markRankingPresented() throws { var draft = ledger; draft.markRankingPresented(writer: writer); if draft != ledger { try commit(draft) } }
    func resumeRanking() throws { var draft = ledger; draft.normalizeInboxRanking(writer: writer); if draft != ledger { try commit(draft) } }
    func replenishTopTen() throws { var draft = ledger; draft.replenishTopTen(writer: writer); if draft != ledger { try commit(draft) } }
    func chooseCapture(_ preferred: String, pair: RankingPair) throws {
        var draft = ledger; draft.chooseCapture(preferred, from: pair, writer: writer); try commit(draft)
    }
    func rerankCapture(_ id: String) throws { var draft = ledger; draft.rerankCapture(id, writer: writer); try commit(draft) }

    func restoreBackup(_ data: Data) throws {
        let saved = try LedgerBackup.decode(data)
        let recovery = file.deletingLastPathComponent().appendingPathComponent("ledger-before-restore-\(UUID().uuidString).json")
        if FileManager.default.fileExists(atPath: file.path) { try Data(contentsOf: file).write(to: recovery, options: [.atomic]) }
        var draft = ledger; draft.merge(saved.ledger); draft.prepareGroupSuggestions(writer: writer)
        draft.normalizeInboxRanking(writer: writer)
        // An explicitly selected backup can recover an unreadable ledger while
        // retaining its original bytes in a separate recovery file.
        try JSONEncoder().encode(draft).write(to: file, options: [.atomic])
        ledger = draft; storageAvailable = true; error = nil
        start(); refresh()
    }

    func saveCategory(id: String?, name: String) throws {
        var draft = ledger; try draft.saveCategory(id: id, name: name, writer: writer); try commit(draft)
    }

    func editCategory(id: String?, name: String, parent: String?) throws {
        var draft = ledger
        try draft.saveCategory(id: id, name: name, writer: writer)
        if let categoryID = id ?? draft.categories.last?.id {
            if draft.categoryParents[categoryID] != parent { try draft.moveCategory(categoryID, to: parent, writer: writer) }
        }
        try commit(draft)
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
                  original.categoryIDs != updated.categoryIDs || original.categoryID != updated.categoryID || original.categoryAssignment != updated.categoryAssignment else { return nil }
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
                draft.entries[index].categoryIDs = change.before.categoryIDs
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
        let rows = ledger.breakdown(on: ledger.wakingDay(containing: now), now: now).filter { $0.minutes > 0 }.sorted { $0.minutes > $1.minutes }
        guard !rows.isEmpty else { return "Log an activity to start today’s breakdown." }
        let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = ledger.reportingCalendar().timeZone
        stamp.dateFormat = ledger.settings.use24HourTime ? "MMM d, HH:mm" : "MMM d, h:mm a"
        return "Summary as of \(stamp.string(from: now))\n" + rows.map { "\($0.name): \(Int($0.percent.rounded()))% · \(duration($0.minutes))" }.joined(separator: "\n")
    }
    func time(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ledger.reportingCalendar().timeZone
        formatter.dateFormat = ledger.settings.use24HourTime ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
    func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium
        formatter.timeZone = ledger.reportingCalendar().timeZone
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
