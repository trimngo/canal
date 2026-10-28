import Foundation
import Combine
#if DEBUG
import UserNotifications
#endif
import LedgerCore
#if os(watchOS)
import WidgetKit
import WatchKit
#endif

@MainActor
final class LedgerStore: ObservableObject {
    static let shared = LedgerStore()
    @Published private(set) var ledger = Ledger() { didSet { inboxCache = nil } }
    private var inboxCache: (snapshot: InboxRankingSnapshot, nextReturn: Date?, timeZone: String)?
    var inbox: InboxRankingSnapshot {
        if let cached = inboxCache, cached.timeZone == Calendar.current.timeZone.identifier, cached.nextReturn.map({ $0 > Date() }) ?? true { return cached.snapshot }
        let snapshot = ledger.inboxSnapshot
        inboxCache = (snapshot, ledger.snoozedCaptures.first?.snoozeReturnDate(), Calendar.current.timeZone.identifier)
        return snapshot
    }
    @Published var sampleRequestID = UUID()
    @Published var pendingLogRequest = false
    @Published var timerRequestID = UUID()
    @Published var showingTimerQueue = false
    @Published var timerDictationRequested = false
    @Published var timerRoutingStatus = ""
    @Published var timerRoutingBusy = false
    private var timerSupportInitialized = false
    private var timerSupportSystemAlarms = false
    private var timerSupportSystemAlarmSilent = false
    private var timerSupportControl: TimerQueueControl?
    private var timerSupportTask: QueuedTimer?
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
    @Published private(set) var categoryMoveUndo: CategoryMoveUndo?
    var canUndoCategoryMove: Bool { categoryMoveUndo.map { ledger.canUndoCategoryMove($0) } ?? false }
    private var groupingUndo: [(before: CheckIn, after: CheckIn)] = []
    private let file: URL
    let writer: String
    private var saveObserver: (() -> Void)?
    #if os(iOS)
    private var automaticCategoryWork: Task<Void, Never>?
    #endif
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
                defaults.removeObject(forKey: "notifications.urgent-history.v1")
                defaults.removeObject(forKey: "timers.system-alarm.record")
                defaults.removeObject(forKey: "timers.system-alarm.silenced")
                defaults.removeObject(forKey: "timers.watch-override-task")
                // Notification tests must not cover the next test's input UI.
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-urgent-inbox") {
                var fixture = Ledger()
                fixture.categories = [LedgerCategory(id: "music", name: "Music")]
                for (id, text) in [("alan", "Get back to Alan"), ("joe", "Reply back to Joe"), ("rent", "Pay the rent"), ("guitar", "Practice guitar")] {
                    try fixture.addCapture(text: text, id: id, writer: "fixture")
                }
                var ranking = InboxRanking(); ranking.ordered = ["guitar"]
                ranking.revision = fixture.nextRevision(writer: "fixture"); fixture.inboxRanking = ranking
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-daily-goals") }) {
                defaults.removeObject(forKey: "goals.display-unit")
                var fixture = Ledger()
                fixture.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"),
                                      LedgerCategory(id: "music", name: "Music"), LedgerCategory(id: "food", name: "Eating")]
                try fixture.moveCategory("teaching", to: "work", writer: "fixture")
                fixture.settings.reportingTimeZoneIdentifier = "UTC"
                fixture.settings.inferenceMethod = .carryForward
                fixture.settings.use24HourTime = true
                fixture.settings.notificationsAllDay = true
                let stamp = ISO8601DateFormatter(), day = stamp.date(from: "2026-10-22T00:00:00Z")!
                let now = stamp.date(from: "2026-10-22T17:30:00Z")!
                for (minute, id) in [(427.5, "music"), (480.0, "teaching"), (600.0, "food"), (1042.5, "food")] {
                    try fixture.saveSample(at: day.addingTimeInterval(minute * 60), activity: "\(id) observation", categoryIDs: [id], writer: "fixture", now: now)
                }
                let args = ProcessInfo.processInfo.arguments
                let goals: [String: Double]
                if args.contains("--ui-daily-goals-overflow") { goals = ["music": 50, "teaching": 50] }
                else if args.contains("--ui-daily-goals-proportional") { goals = ["music": 10, "teaching": 20, "food": 0] }
                else if args.contains("--ui-daily-goals-completed") { goals = ["music": 5, "teaching": 10, "food": 0] }
                else { goals = ["music": 20, "teaching": 20] }
                try fixture.saveAllocationGoals(goals, effectiveAt: day.addingTimeInterval(-86400), writer: "fixture")
                try fixture.setCategoryFavorites(Set(goals.keys), favorite: true, writer: "fixture")
                if args.contains("--ui-daily-goals-large-editor") {
                    for group in 0..<10 {
                        let parent = "area-\(group)"
                        fixture.categories.append(LedgerCategory(id: parent, name: "Area \(group)"))
                        for item in 0..<10 {
                            var category = LedgerCategory(id: "detail-\(group)-\(item)", name: "Activity \(group)-\(item)")
                            category.parentID = parent
                            fixture.categories.append(category)
                        }
                    }
                    for offset in -7...0 {
                        for sample in 0..<72 {
                            let id = "detail-\(sample / 10)-\(sample % 10)"
                            fixture.entries.append(CheckIn(end: day.addingTimeInterval(Double(offset * 86400 + (7 * 60 + sample * 12) * 60)),
                                activity: "History observation \(sample)", categoryID: id, revision: Revision(counter: Int64(fixture.entries.count + 1), writer: "fixture"),
                                sampleID: "history-\(offset)-\(sample)", categoryAssignment: .manual))
                        }
                    }
                }
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-category-workspace") {
                var fixture = Ledger()
                fixture.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"),
                    LedgerCategory(id: "admin", name: "Admin"), LedgerCategory(id: "music", name: "Music")]
                try fixture.moveCategory("teaching", to: "work", writer: "fixture")
                try fixture.moveCategory("admin", to: "work", writer: "fixture")
                let now = Date(), day = Calendar.current.startOfDay(for: now)
                try fixture.saveSample(id: "teaching-log", at: min(now, day.addingTimeInterval(60)), activity: "Preparing classes", categoryIDs: ["teaching"], writer: "fixture", now: now)
                try fixture.saveSample(id: "music-log", at: now.addingTimeInterval(-1), activity: "Playing music", categoryIDs: ["music"], writer: "fixture", now: now)
                try fixture.saveAllocationGoals(["music": 20, "teaching": 20, "admin": 0], effectiveAt: now.addingTimeInterval(-86400), writer: "fixture")
                for (i, pair) in [("uncategorized", "Newest uncategorized idea"), ("unseen", "New music idea"),
                                  ("first", "Important music idea"), ("second", "Prepare a class"),
                                  ("reference", "Music reference note"), ("completed", "Completed music idea")].enumerated() {
                    try fixture.addCapture(text: pair.1, id: pair.0, writer: "fixture", now: now.addingTimeInterval(Double(-i * 60)))
                }
                for id in ["first", "unseen", "reference", "completed"] { try fixture.categorizeCapture(id: id, categoryIDs: ["music"], writer: "fixture") }
                try fixture.categorizeCapture(id: "second", categoryIDs: ["teaching"], writer: "fixture")
                fixture.setCaptureDone(id: "completed", done: true, writer: "fixture")
                fixture.setCaptureReference("reference", reference: true, writer: "fixture")
                var ranking = InboxRanking(); ranking.ordered = ["first", "second"]
                ranking.revision = fixture.nextRevision(writer: "fixture"); fixture.inboxRanking = ranking
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") }) {
                defaults.removeObject(forKey: "dashboard.hide-zero-time")
                defaults.removeObject(forKey: "commitments.hide-zero-time")
                defaults.removeObject(forKey: "commitments.sort-column")
                defaults.removeObject(forKey: "commitments.sort-descending")
            }
            if ProcessInfo.processInfo.arguments.contains(where: { ["--ui-empty-ledger", "--ui-allocation-fixture", "--ui-life-area-fixture", "--ui-commitments-fixture", "--ui-goal-hours-fixture", "--ui-allocation-sort-fixture"].contains($0) }) {
                defaults.removeObject(forKey: "goals.display-unit")
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-zero-category-fixture") {
                defaults.removeObject(forKey: "goals.display-unit")
                var fixture = Ledger()
                fixture.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"),
                    LedgerCategory(id: "admin", name: "Administration"), LedgerCategory(id: "music", name: "Music"),
                    LedgerCategory(id: "guitar", name: "Guitar"), LedgerCategory(id: "food", name: "Eating")]
                for index in 0..<30 { fixture.categories.append(LedgerCategory(id: "unused-\(index)", name: String(format: "Unused %02d", index))) }
                try fixture.moveCategory("teaching", to: "work", writer: "fixture")
                try fixture.moveCategory("admin", to: "work", writer: "fixture")
                try fixture.moveCategory("guitar", to: "music", writer: "fixture")
                fixture.settings.reportingTimeZoneIdentifier = "UTC"
                let now = Date(), day = fixture.reportingDay(containing: now)
                try fixture.saveSample(at: max(day, now.addingTimeInterval(-300)), activity: "Teaching now", categoryIDs: ["teaching"], writer: "fixture", now: now)
                try fixture.saveSample(at: day.addingTimeInterval(-43200), activity: "Eating yesterday", categoryIDs: ["food"], writer: "fixture", now: now)
                try fixture.saveAllocationGoals(["guitar": 25, "unused-0": 0], writer: "fixture")
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-goal-hours-fixture") || ProcessInfo.processInfo.arguments.contains("--ui-allocation-sort-fixture") {
                var fixture = Ledger()
                fixture.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"), LedgerCategory(id: "music", name: "Music"), LedgerCategory(id: "food", name: "Eating")]
                try fixture.moveCategory("teaching", to: "work", writer: "fixture")
                var settings = fixture.settings; settings.reportingTimeZoneIdentifier = "UTC"; settings.inferenceMethod = .carryForward
                try fixture.saveSettings(settings, writer: "fixture")
                var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
                let now = Date(), today = cal.startOfDay(for: now)
                for offset in -3 ... -1 {
                    let day = cal.date(byAdding: .day, value: offset, to: today)!
                    for (minute, id) in [(427.5, "teaching"), (660.0, "music"), (720.0, "food"), (1252.5, "food")] {
                        try fixture.saveSample(at: day.addingTimeInterval(minute * 60), activity: "\(id) observation", categoryIDs: [id], writer: "fixture", now: now)
                    }
                }
                try fixture.saveSample(at: max(today, now.addingTimeInterval(-3600)), activity: "Today teaching", categoryIDs: ["teaching"], writer: "fixture", now: now)
                try fixture.saveSample(at: now, activity: "Today music", categoryIDs: ["music"], writer: "fixture", now: now)
                if ProcessInfo.processInfo.arguments.contains("--ui-allocation-sort-fixture") {
                    fixture.categories.append(LedgerCategory(id: "admin", name: "Administration"))
                    try fixture.moveCategory("admin", to: "work", writer: "fixture")
                    try fixture.saveAllocationGoals(["teaching": 20, "admin": 5, "music": 10], writer: "fixture")
                } else {
                    try fixture.saveAllocationGoals(["teaching": 20, "music": 10], writer: "fixture")
                }
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if (ProcessInfo.processInfo.arguments.contains("--ui-dated-goals-fixture") || ProcessInfo.processInfo.arguments.contains("--ui-feedback-fixture")) {
                var fixture = Ledger(); fixture.settings.reportingTimeZoneIdentifier = "UTC"
                let now = Date()
                let goal = try fixture.saveDatedGoal(name: "Prepare DIGS lecture", categoryID: "work", targetMinutes: 240,
                    startDate: now.addingTimeInterval(-3 * 86400), deadline: now.addingTimeInterval(3 * 86400), writer: "fixture")
                try fixture.saveDatedGoal(name: "Prepare SDES lecture", categoryID: "work", targetMinutes: 240,
                    startDate: now.addingTimeInterval(-3 * 86400), deadline: now.addingTimeInterval(5 * 86400), writer: "fixture")
                let completed = CalendarEventSnapshot(id: "ui-completed", calendarID: "fixture", calendarName: "Classes", title: "DIGS preparation",
                    start: now.addingTimeInterval(-10800), end: now.addingTimeInterval(-7200))
                let pending = CalendarEventSnapshot(id: "ui-pending", calendarID: "fixture", calendarName: "Classes", title: "Calendar lecture to confirm",
                    start: now.addingTimeInterval(-5400), end: now.addingTimeInterval(-1800))
                fixture.collectCalendarEvents([completed, pending], writer: "fixture", now: now)
                try fixture.decideCalendarEvent(completed.id, confirm: true, goalID: goal, writer: "fixture", now: now)
                try fixture.saveSample(id: "ui-goal-review", at: now.addingTimeInterval(-60), activity: "Preparing slides to categorize", categoryID: nil, writer: "fixture", now: now)
                try fixture.saveAllocationGoals(["work": 20], writer: "fixture")
                if ProcessInfo.processInfo.arguments.contains("--ui-feedback-fixture") {
                    for index in 0..<30 { fixture.categories.append(LedgerCategory(id: "extra-\(index)", name: String(format: "Extra category %02d", index))) }
                    try fixture.setCategoryFavorites(["work"], favorite: true, writer: "fixture")
                    let sample = fixture.entries.first { $0.id == "ui-goal-review" }!
                    try fixture.suggestCategories(CategorySuggestion(categoryIDs: ["work"], reason: "Matched confirmed vocabulary: preparing, slides", sourceText: sample.activity), logID: sample.id, writer: "fixture")
                    for day in 1...7 {
                        try fixture.saveSample(id: "comparison-\(day)", at: now.addingTimeInterval(Double(-day * 86400)), activity: "Music practice", categoryIDs: ["leisure"], writer: "fixture", now: now)
                    }
                }
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-empty-ledger") {
                try JSONEncoder().encode(Ledger()).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-today-urgent") {
                var fixture = Ledger()
                fixture.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"), LedgerCategory(id: "music", name: "Music")]
                try fixture.moveCategory("teaching", to: "work", writer: "fixture")
                for (id, text) in [("alan", "Get back to Alan"), ("joe", "Reply to Joe"), ("rent", "Pay the rent"), ("guitar", "Practice guitar")] {
                    try fixture.addCapture(text: text, id: id, writer: "fixture")
                }
                try fixture.categorizeCapture(id: "alan", categoryIDs: ["teaching"], writer: "fixture")
                try fixture.categorizeCapture(id: "joe", categoryIDs: ["music", "teaching"], writer: "fixture")
                try fixture.categorizeCapture(id: "guitar", categoryIDs: ["music"], writer: "fixture")
                try fixture.saveSample(at: Date().addingTimeInterval(-1200), activity: "Today log waiting for review", categoryIDs: [], writer: "fixture")
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-watch-notification-ledger") || ProcessInfo.processInfo.arguments.contains("--ui-watch-automatic-notification-ledger") {
                var fixture = Ledger()
                var settings = fixture.settings
                settings.notificationTiming = .randomized; settings.notificationsAllDay = true; settings.notificationsEnabled = true
                settings.notificationDelivery = ProcessInfo.processInfo.arguments.contains("--ui-watch-automatic-notification-ledger") ? .automatic : .watch
                try fixture.saveSettings(settings, writer: "fixture")
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-urgent-checkins") {
                var fixture = Ledger()
                for (id, text) in [("checkin-class", "Reschedule the class"), ("checkin-rent", "Pay rent"),
                                   ("checkin-reply", "Reply to Jo"), ("ordinary", "Practice scales")] {
                    try fixture.addCapture(text: text, id: id, writer: "fixture")
                }
                try fixture.setCaptureTiming("checkin-rent", timing: .due(Date().addingTimeInterval(-3600)), writer: "fixture")
                try fixture.setCaptureTiming("checkin-class", timing: .due(Date().addingTimeInterval(3600)), writer: "fixture")
                var settings = fixture.settings
                settings.notificationsEnabled = true; settings.notificationsAllDay = false
                // Keep real notifications away from UI interactions, at least
                // 90 minutes ahead, without replacing the actual scheduler.
                let clock = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date())
                settings.startMinute = ((clock / 30 + 4) % 46) * 30
                settings.endMinute = settings.startMinute + 60
                settings.regularNotificationInterval = 30
                try fixture.saveSettings(settings, writer: "fixture")
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-legacy-ledger") {
                var fixture = Ledger(); fixture.schemaVersion = 1
                fixture.entries = [CheckIn(end: Ledger.slotEnd(at: Date()), activity: "Legacy sample UI fixture", categoryID: "work", revision: Revision(counter: 1, writer: "fixture"))]
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-legacy-sleep-windows") {
                var fixture = Ledger(); fixture.settings.reportingTimeZoneIdentifier = "UTC"
                let now = Date(), calendar = fixture.reportingCalendar(), day = calendar.startOfDay(for: now)
                let early = min(day.addingTimeInterval(3600), max(day, now.addingTimeInterval(-600)))
                try fixture.saveSample(id: "early", at: early, activity: "Before former wake time", categoryID: "work", writer: "fixture", now: now)
                try fixture.saveSample(id: "late", at: day.addingTimeInterval(-1800), activity: "After former bedtime", categoryID: "social", writer: "fixture", now: now)
                var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture)) as! [String: Any]
                var settings = json["settings"] as! [String: Any]
                settings["wakeUpMinute"] = 420; settings["bedtimeMinute"] = 1320; json["settings"] = settings
                json["wakingOverrides"] = [["id": "legacy", "wakeMinute": 600, "bedMinute": 660, "reset": false, "revision": ["counter": 1, "writer": "fixture"]]]
                try JSONSerialization.data(withJSONObject: json).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-grouping-ledger") || ProcessInfo.processInfo.arguments.contains("--ui-review-range-fixture") || ProcessInfo.processInfo.arguments.contains("--ui-long-grouping-ledger") {
                var fixture = Ledger()
                let now = Date()
                try fixture.saveSample(at: now.addingTimeInterval(-3600), activity: "Preparing classes", categoryID: "work", writer: "fixture", now: now)
                let longEntry = "Preparing classes and writing notes about the lesson. " + String(repeating: "Include the examples and follow-up questions for next week. ", count: 7)
                let activity = ProcessInfo.processInfo.arguments.contains("--ui-long-grouping-ledger") ? longEntry : "Quokka activity fixture"
                try fixture.saveSample(at: now.addingTimeInterval(-1800), activity: activity, categoryID: nil, writer: "fixture", now: now)
                if ProcessInfo.processInfo.arguments.contains("--ui-review-range-fixture") {
                    try fixture.saveSample(id: "older-pending", at: now.addingTimeInterval(-86400), activity: "Older ungrouped observation", categoryID: nil, writer: "fixture", now: now)
                }
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-trend-fixture") || ProcessInfo.processInfo.arguments.contains("--ui-many-trends-fixture") {
                for key in ["history.trend.categories.v1", "history.trend.percent", "history.trend.layout"] { defaults.removeObject(forKey: key) }
                var fixture = Ledger()
                let now = Date(), calendar = Calendar.current
                for offset in 0...6 where offset != 3 {
                    let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now))!
                    let first = offset == 0 ? max(day, now.addingTimeInterval(-7200)) : day.addingTimeInterval(9 * 3600)
                    let second = offset == 0 ? max(first, now.addingTimeInterval(-3600)) : day.addingTimeInterval(Double(11 + offset) * 3600)
                    if ProcessInfo.processInfo.arguments.contains("--ui-many-trends-fixture") {
                        for (index, category) in fixture.categories.enumerated() {
                            let stamp = offset == 0 ? first.addingTimeInterval(max(0, now.timeIntervalSince(first) - 60) * Double(index) / Double(fixture.categories.count)) : day.addingTimeInterval(Double(9 + index * 2) * 3600)
                            try fixture.saveSample(at: stamp, activity: "\(category.name) observation", categoryID: category.id, writer: "fixture", now: now)
                        }
                    } else {
                        try fixture.saveSample(at: first, activity: "Work observation", categoryID: "work", writer: "fixture", now: now)
                        try fixture.saveSample(at: second, activity: "Social observation", categoryID: "social", writer: "fixture", now: now)
                    }
                }
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-snooze-today") {
                var fixture = Ledger()
                try fixture.addCapture(text: "Due at beginning of today", id: "due-today", writer: "fixture")
                fixture.captures[0].snoozedUntil = Calendar.current.startOfDay(for: Date()).addingTimeInterval(20 * 3600)
                fixture.captures[0].reviewRevision = fixture.nextRevision(writer: "fixture")
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-group-history") {
                var fixture = Ledger()
                try fixture.saveSample(id: "older", at: Date().addingTimeInterval(-10 * 86400), activity: "Older work observation", categoryID: "work", writer: "fixture")
                try fixture.saveSample(id: "recent", at: Date().addingTimeInterval(-60), activity: "Recent work observation", categoryID: "work", writer: "fixture")
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-allocation-fixture") || ProcessInfo.processInfo.arguments.contains("--ui-commitments-fixture") || ProcessInfo.processInfo.arguments.contains("--ui-life-area-fixture") {
                var fixture = Ledger(); fixture.categories = [LedgerCategory(id: "work", name: "Work"), LedgerCategory(id: "teaching", name: "Teaching"), LedgerCategory(id: "music", name: "Music")]
                try fixture.moveCategory("teaching", to: "work", writer: "fixture")
                let now = Date(), cal = Calendar.current
                let first = cal.startOfDay(for: now).addingTimeInterval(60)
                try fixture.saveSample(id: "today-teaching", at: min(first, now), activity: "Preparing classes", categoryIDs: ["teaching"], writer: "fixture", now: now)
                try fixture.saveSample(id: "today-music", at: now.addingTimeInterval(-1), activity: "Guitar practice", categoryIDs: ["music"], writer: "fixture", now: now)
                if let yesterday = cal.date(byAdding: .day, value: -1, to: first) {
                    try fixture.saveSample(at: yesterday, activity: "Yesterday work", categoryIDs: ["work"], writer: "fixture", now: now)
                }
                try fixture.saveAllocationGoals(["teaching": 30, "music": 15], effectiveAt: now.addingTimeInterval(-60), writer: "fixture")
                if ProcessInfo.processInfo.arguments.contains("--ui-life-area-fixture") {
                    fixture.categories += [LedgerCategory(id: "admin", name: "Administration"), LedgerCategory(id: "health", name: "Health"), LedgerCategory(id: "german", name: "German")]
                    try fixture.saveAllocationGoals(["teaching": 30, "music": 15, "admin": 10, "health": 45], writer: "fixture")
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-commitments-fixture") {
                    try fixture.saveWeeklyCommitment(categoryID: "work", minimumMinutes: 60, writer: "fixture")
                    try fixture.saveWeeklyCommitment(categoryID: "music", minimumMinutes: 600, writer: "fixture")
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-category-outline") {
                    try fixture.moveCategory("music", to: "work", writer: "fixture")
                    fixture.categories.append(LedgerCategory(id: "guitar", name: "Guitar"))
                    try fixture.moveCategory("guitar", to: "music", writer: "fixture")
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-heatmap-detail") {
                    let span = max(0, now.timeIntervalSince(first))
                    try fixture.saveSample(id: "today-guitar", at: min(now, first.addingTimeInterval(span * 0.35)),
                        activity: "Practicing guitar", categoryIDs: ["guitar"], writer: "fixture", now: now)
                    try fixture.saveSample(id: "today-parent-direct", at: min(now, first.addingTimeInterval(span * 0.65)),
                        activity: "Work without a subcategory", categoryIDs: ["work"], writer: "fixture", now: now)
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
                for index in 1...24 {
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
                for index in 1...36 {
                    let id = "priority-\(index)"
                    try fixture.addCapture(text: "Priority \(index)", id: id, writer: "fixture", now: Date().addingTimeInterval(Double(index - 60)))
                    if index <= InboxRanking.priorityLimit { ranking.ordered.append(id) }
                }
                let tail = (11...36).map { "priority-\($0)" }
                let legacy: [String: Any] = ["backlog": tail, "preferences": tail.map { ["winner": "priority-20", "loser": $0] }, "pending": [], "replenishing": false]
                ranking.topTen = try JSONDecoder().decode(TopTenRanking.self, from: JSONSerialization.data(withJSONObject: legacy))
                ranking.revision = fixture.nextRevision(writer: "fixture"); fixture.inboxRanking = ranking
                fixture.prepareRanking(writer: "fixture")
                fixture.setCaptureDone(id: "priority-1", done: true, writer: "fixture")
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-screening-inbox-fixture") {
                var fixture = Ledger(), ranked = InboxRanking()
                let now = Date()
                for index in 1...22 {
                    let id = "screening-\(index)"
                    try fixture.addCapture(text: "Priority \(index)", id: id, writer: "fixture", now: now.addingTimeInterval(Double(index - 60)))
                    ranked.ordered.append(id)
                }
                ranked.revision = fixture.nextRevision(writer: "fixture"); fixture.inboxRanking = ranked
                fixture.prepareRanking(writer: "fixture")
                if let pair = fixture.rankingPair {
                    fixture.chooseCapture(pair.second, from: pair, writer: "fixture", now: now.addingTimeInterval(-18 * 86400))
                }
                try fixture.addCapture(text: "One quick new idea", id: "quick-new", writer: "fixture")
                fixture.prepareRanking(writer: "fixture")
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
            if ProcessInfo.processInfo.arguments.contains("--ui-timer-fixture") {
                var fixture = Ledger()
                let earlier = Date().addingTimeInterval(-1500)
                try fixture.enqueueTimer(id: "timer-guitar", title: "Practice guitar", duration: 1200, writer: writer, onWatch: Self.isWatch, now: earlier)
                try fixture.enqueueTimer(id: "timer-email", title: "Answer email", duration: 600, writer: writer, onWatch: Self.isWatch, now: earlier.addingTimeInterval(1))
                try fixture.enqueueTimer(id: "timer-walk", title: "Take a walk", duration: 300, writer: writer, onWatch: Self.isWatch, now: earlier.addingTimeInterval(2))
                if ProcessInfo.processInfo.arguments.contains("--ui-timer-long-queue") {
                    for index in 1...8 {
                        try fixture.enqueueTimer(id: "timer-extra-\(index)", title: "Queued task \(index)", duration: 300,
                            writer: writer, onWatch: Self.isWatch, now: earlier.addingTimeInterval(Double(index + 2)))
                    }
                }
                if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-alarmkit-") }) {
                    fixture.settings.timerSystemAlarms = !ProcessInfo.processInfo.arguments.contains("--ui-alarmkit-denied")
                    fixture.restartTimer(writer: writer, onWatch: Self.isWatch)
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-watch-owned-timer") {
                    fixture.moveTimerAlerts(writer: "paired-watch", onWatch: true)
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-phone-owned-timer") {
                    fixture.moveTimerAlerts(writer: "paired-phone", onWatch: false)
                }
                try JSONEncoder().encode(fixture).write(to: file, options: [.atomic])
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-timer-long-title") {
                var fixture = Ledger()
                let title = "Prepare the complete presentation for the project review with the design team tomorrow morning"
                try fixture.enqueueTimer(id: "long-title", title: title, duration: 300, writer: writer, onWatch: Self.isWatch)
                if ProcessInfo.processInfo.arguments.contains("--ui-timer-waiting") {
                    fixture.timerControl = nil
                }
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
                if let ranking = loaded.inboxRanking, ranking.screeningReview == nil {
                    let recovery = directory.appendingPathComponent("ledger-before-screening-review.json")
                    if !FileManager.default.fileExists(atPath: recovery.path) { try original.write(to: recovery, options: [.atomic]) }
                }
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
            draft.migrateGoalsToTasks(writer: writer)
            if draft.settings.reportingTimeZoneIdentifier == nil {
                var settings = draft.settings; settings.reportingTimeZoneIdentifier = TimeZone.current.identifier
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
                #endif
                if let self {
                    do { try await NotificationScheduler.shared.apply(self.ledger.settings) } catch { self.report(error) }
                }
            }
        }
        importSiriCaptures()
        companion?.start(); cloud?.requestSync()
        refreshTimerSupport(force: true)
        #if os(iOS)
        scheduleAutomaticCategories()
        #endif
        #if os(iOS)
        if storageAvailable { backup?.request(ledger) }
        #endif
    }

    func refresh() {
        start(); importSiriCaptures(); companion?.refresh(); cloud?.requestSync()
        refreshTimerSupport(force: true)
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
        // The unsigned Watch simulator cannot access the device-only Siri queue.
        #if os(watchOS) && !targetEnvironment(simulator)
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
        draft.migrateGoalsToTasks(writer: writer)
        draft.normalizeInboxRanking(writer: writer)
        try JSONEncoder().encode(draft).write(to: file, options: [.atomic])
        ledger = draft
        if started { refreshTimerSupport() }
        #if os(iOS)
        scheduleAutomaticCategories()
        #endif
        saveObserver?()
    }

    #if os(iOS)
    private func scheduleAutomaticCategories() {
        automaticCategoryWork?.cancel()
        guard started, !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") }) else { return }
        let snapshot = ledger
        automaticCategoryWork = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            let results = await AutomaticCategories.shared.classify(snapshot)
            guard !Task.isCancelled, let self else { return }
            var draft = self.ledger
            // Verify source revisions after background work; never overwrite an
            // edit, confirmation, deletion or sync that arrived in the meantime.
            for (id, suggestion) in results.logs {
                guard snapshot.entries.first(where: { $0.id == id })?.revision == draft.entries.first(where: { $0.id == id })?.revision else { continue }
                try? draft.suggestCategories(suggestion, logID: id, writer: self.writer)
            }
            for (id, suggestion) in results.ideas {
                guard snapshot.captures.first(where: { $0.id == id })?.revision == draft.captures.first(where: { $0.id == id })?.revision else { continue }
                try? draft.suggestCategories(suggestion, captureID: id, writer: self.writer)
            }
            if draft != self.ledger { do { try self.commit(draft) } catch { self.report(error) } }
        }
    }
    #endif

    func merge(_ incoming: Ledger) throws {
        guard (1...2).contains(incoming.schemaVersion) else { throw StoreError.unsupportedVersion }
        var draft = ledger; draft.merge(incoming)
        draft.normalizeInboxRanking(writer: writer)
        draft.prepareGroupSuggestions(writer: writer)
        if draft != ledger { try commit(draft) }
    }

    func beginSample() { pendingLogRequest = true; sampleRequestID = UUID() }

    static var isWatch: Bool {
        #if os(watchOS)
        return true
        #else
        return false
        #endif
    }
    func openTimers(dictate: Bool = false) {
        start(); timerDictationRequested = dictate; showingTimerQueue = true; timerRequestID = UUID()
    }
    func addTimer(_ text: String) throws {
        let parsed = try TimerDraft.parse(text)
        start(); let previousToken = ledger.timerControl?.token; var draft = ledger
        try draft.enqueueTimer(title: parsed.title, duration: parsed.duration, writer: writer, onWatch: Self.isWatch)
        try commit(draft)
        if draft.timerControl?.token != previousToken { offerPhoneAlarmIfPreferred() }
    }
    func changeTimer(_ action: String, expectedToken: String? = nil) throws {
        start()
        // A repeated notification callback must not complete a newer task.
        guard expectedToken == nil || expectedToken == ledger.timerControl?.token else { return }
        var draft = ledger
        switch action {
        case "done": draft.finishTimer(writer: writer, onWatch: Self.isWatch)
        case "restart": draft.restartTimer(writer: writer, onWatch: Self.isWatch)
        case "pause": draft.pauseTimer(writer: writer, onWatch: Self.isWatch)
        case "resume": draft.resumeTimer(writer: writer, onWatch: Self.isWatch)
        case "start": draft.startNextTimer(writer: writer, onWatch: Self.isWatch)
        case "here": draft.moveTimerAlerts(writer: writer, onWatch: Self.isWatch)
        default: return
        }
        if draft != ledger {
            try commit(draft)
            #if os(watchOS)
            if action == "here" { UserDefaults.standard.set(draft.currentTimer?.id, forKey: "timers.watch-override-task") }
            #endif
            if ["start", "resume", "restart", "done"].contains(action) { offerPhoneAlarmIfPreferred() }
        }
    }
    func completeStoppedSystemAlarm(expectedToken: String) throws {
        var draft = ledger
        draft.completeStoppedSystemAlarm(expectedToken: expectedToken, writer: writer)
        if draft != ledger { try commit(draft) }
    }
    #if DEBUG && os(iOS)
    func expireSystemAlarmForUITest() throws {
        guard ProcessInfo.processInfo.arguments.contains("--ui-system-alarm-expired") else { return }
        var draft = ledger; draft.timerControl?.dueAt = Date().addingTimeInterval(-1)
        try commit(draft)
    }
    #endif
    private func offerPhoneAlarmIfPreferred() {
        #if os(watchOS)
        guard PhoneTimerAlarmPolicy.canOfferPhone(ledger, writer: writer,
            isActive: WKApplication.shared().applicationState == .active,
            watchOverrideTaskID: UserDefaults.standard.string(forKey: "timers.watch-override-task")) else { return }
        usePhoneTimerAlarm(manual: false)
        #endif
    }
    func usePhoneTimerAlarm(manual: Bool = true) {
        #if os(watchOS)
        guard !timerRoutingBusy, let token = ledger.timerControl?.token,
              ledger.timerControl?.onWatch == true else { return }
        timerRoutingBusy = true; timerRoutingStatus = "Checking iPhone · Watch alarm stays scheduled"
        Task { @MainActor in
            defer { self.timerRoutingBusy = false }
            do {
                guard let companion = self.companion else { throw TimerAlarmTransferError.unavailable }
                let incoming = try await companion.requestPhoneTimerAlarm(token: token)
                if self.ledger.timerControl?.token == token || self.ledger.timerControl == incoming.timerControl {
                    try self.merge(incoming)
                }
                self.timerRoutingStatus = self.ledger.timerControl?.onWatch == false
                    ? "iPhone system alarm confirmed"
                    : "Watch alarm retained · timer changed during handover"
                if manual, self.ledger.timerControl?.onWatch == false {
                    UserDefaults.standard.removeObject(forKey: "timers.watch-override-task")
                }
            } catch {
                self.timerRoutingStatus = self.ledger.timerControl?.onWatch == true
                    ? "Watch alarm retained · iPhone could not confirm an alarm"
                    : "Check current alert destination · iPhone reply unavailable"
            }
        }
        #endif
    }
    #if os(iOS)
    func acceptPhoneTimerAlarm(_ incoming: Ledger, expectedToken: String, offerID: String, expiresAt: Date) async throws -> Ledger {
        start()
        guard PhoneTimerAlarmPolicy.offerCanCommit(expiresAt: expiresAt) else { throw TimerAlarmTransferError.unavailable }
        try merge(incoming)
        guard ledger.settings.timerSystemAlarms, ledger.timerControl?.token == expectedToken,
              let old = ledger.timerControl,
              PhoneTimerAlarmPolicy.canOfferPhone(ledger, writer: old.owner, isActive: true) else {
            throw TimerAlarmTransferError.changed
        }
        let base = ledger
        var candidate = base; candidate.moveTimerAlerts(writer: writer, onWatch: false)
        guard let proposed = candidate.timerControl else { throw TimerAlarmTransferError.changed }
        let alarms = PhoneTimerAlarm.shared
        let armed = try await alarms.prepare(candidate, writer: writer)
        let watchReady = armed && PhoneTimerAlarmPolicy.offerCanCommit(expiresAt: expiresAt)
            ? await companion?.watchCanFinishAlarmHandoff(token: expectedToken, offerID: offerID) == true : false
        guard armed, watchReady, PhoneTimerAlarmPolicy.offerCanCommit(expiresAt: expiresAt),
              alarms.preparationIsValid(proposed.token), ledger == base,
              PhoneTimerAlarmPolicy.acceptsHandoff(ledger, expectedToken: expectedToken,
                                                   candidate: candidate, phoneWriter: writer) else {
            await alarms.abandonPreparation(proposed.token)
            refreshTimerSupport(force: true)
            throw TimerAlarmTransferError.unavailable
        }
        do { try commit(candidate) }
        catch {
            await alarms.abandonPreparation(proposed.token)
            refreshTimerSupport(force: true)
            throw error
        }
        alarms.finishPreparation(proposed.token)
        await TimerLiveActivity.shared.refresh(ledger)
        await NotificationScheduler.shared.applyTimer(ledger, writer: writer)
        return ledger
    }
    #endif
    func deleteTimer(_ id: String) throws {
        var draft = ledger; draft.deleteQueuedTimer(id, writer: writer, onWatch: Self.isWatch)
        if draft != ledger { try commit(draft) }
    }
    func editTimer(_ id: String, title: String, duration: TimeInterval) throws {
        var draft = ledger; try draft.editQueuedTimer(id, title: title, duration: duration, writer: writer, onWatch: Self.isWatch)
        if draft != ledger { try commit(draft) }
    }
    func reorderTimers(_ ids: [String]) throws {
        var draft = ledger; draft.reorderWaitingTimers(ids, writer: writer)
        if draft != ledger { try commit(draft) }
    }
    func refreshTimerSupport(force: Bool = false) {
        let current = ledger.currentTimer, control = ledger.timerControl
        guard force || !timerSupportInitialized || timerSupportTask != current || timerSupportControl != control ||
                timerSupportSystemAlarms != ledger.settings.timerSystemAlarms ||
                timerSupportSystemAlarmSilent != ledger.settings.timerSystemAlarmSilent else { return }
        #if os(watchOS)
        if !timerRoutingBusy, timerSupportControl?.token != control?.token { timerRoutingStatus = "" }
        #endif
        timerSupportInitialized = true; timerSupportTask = current; timerSupportControl = control
        timerSupportSystemAlarms = ledger.settings.timerSystemAlarms
        timerSupportSystemAlarmSilent = ledger.settings.timerSystemAlarmSilent
        #if os(watchOS)
        WatchTimerAlarm.shared.update(ledger: ledger, writer: writer)
        #if !targetEnvironment(simulator)
        let snapshot = current.map { TimerWidgetSnapshot(title: $0.title, duration: $0.duration, dueAt: control?.dueAt, pausedRemaining: control?.pausedRemaining) }
        let widgetChanged = (try? TimerWidgetStore.write(snapshot)) == true
        // The shared value can already be correct while WidgetKit is displaying
        // a stale timeline. Foreground refresh must retry that reload too.
        if force || widgetChanged { WidgetCenter.shared.reloadTimelines(ofKind: "DashCurrentTimer") }
        #endif
        #endif
        Task { @MainActor [weak self] in
            guard let self else { return }
            #if os(iOS)
            await TimerLiveActivity.shared.refresh(self.ledger)
            #endif
            await NotificationScheduler.shared.applyTimer(self.ledger, writer: self.writer)
        }
    }

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

    func updateLogActivity(id: String, activity: String) throws {
        var draft = ledger
        try draft.updateLogActivity(id: id, activity: activity, writer: writer)
        if draft != ledger { try commit(draft) }
    }
    func saveTaskPlanning(_ capture: Capture, timing: CaptureTiming?, estimatedMinutes: Double?, startDate: Date?) throws {
        var draft = ledger
        try draft.setCaptureTiming(capture.id, timing: timing, writer: writer)
        try draft.setTaskPlan(capture.id, estimatedMinutes: estimatedMinutes, startDate: startDate, writer: writer)
        try commit(draft)
    }
    func collectCalendarEvents(_ events: [CalendarEventSnapshot]) throws {
        var draft = ledger; draft.collectCalendarEvents(events, writer: writer)
        if draft != ledger { try commit(draft) }
    }
    func decideCalendarEvent(_ id: String, confirm: Bool, categoryIDs: [String] = [], goalID: String? = nil) throws {
        var draft = ledger
        try draft.decideCalendarEvent(id, confirm: confirm, categoryIDs: categoryIDs, writer: writer)
        if confirm, let record = draft.calendarEvents?.first(where: { $0.id == id }) {
            try draft.assignTask(goalID, to: record.logID, writer: writer)
        }
        try commit(draft)
    }
    func reviewCalendarEvent(_ id: String, confirm: Bool, categoryIDs: [String], mood: Int?, goalID: String?, activity: String) throws {
        var draft = ledger
        try draft.decideCalendarEvent(id, confirm: confirm, categoryIDs: categoryIDs, writer: writer)
        if confirm, let entry = draft.calendarEvents?.first(where: { $0.id == id }) {
            try draft.updateLogActivity(id: entry.logID, activity: activity, writer: writer)
            try draft.setMood(for: entry.logID, value: mood, writer: writer)
            try draft.assignTask(goalID, to: entry.logID, writer: writer)
        }
        try commit(draft)
    }
    func reviewLog(_ entry: CheckIn, categoryIDs: [String], mood: Int?, goalID: String?, activity: String? = nil) throws {
        var draft = ledger
        if let activity { try draft.updateLogActivity(id: entry.id, activity: activity, writer: writer) }
        try draft.confirmCategories(for: entry.id, categoryIDs: categoryIDs, writer: writer)
        try draft.setMood(for: entry.id, value: mood, writer: writer)
        try draft.assignTask(goalID, to: entry.id, writer: writer)
        try commitCategorization(draft)
    }
    func saveTargets(_ values: [String: Double]) throws {
        var draft = ledger; try draft.saveTargets(values, writer: writer); try commit(draft)
    }
    func saveAllocationPlan(_ values: [String: Double]) throws {
        var draft = ledger; try draft.saveAllocationPlan(values, writer: writer); try commit(draft)
    }
    func updateAllocationGoal(categoryID: String, percentage: Double?) throws {
        var now = Date()
        #if DEBUG
        // The daily-goal UI fixture renders this frozen instant. Its edits must
        // use the same clock rather than creating budgets in the fixture's future.
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-daily-goals") }) {
            now = ISO8601DateFormatter().date(from: "2026-10-22T17:30:00Z")!
        }
        #endif
        var draft = ledger; try draft.updateAllocationGoal(categoryID: categoryID, percentage: percentage, writer: writer, at: now)
        if draft != ledger { try commit(draft) }
    }
    func setCategoryFavorites(_ ids: Set<String>, favorite: Bool) throws {
        var draft = ledger; try draft.setCategoryFavorites(ids, favorite: favorite, writer: writer)
        if draft != ledger { try commit(draft) }
    }
    func saveAllocationGoals(_ values: [String: Double]) throws {
        var draft = ledger; try draft.saveAllocationGoals(values, writer: writer)
        if draft != ledger { try commit(draft) }
    }
    func groupCategories(_ ids: [String], under parent: String?, newParentName: String? = nil) throws {
        var draft = ledger
        let undo = try draft.groupCategories(ids, under: parent, newParentName: newParentName, writer: writer)
        try commit(draft)
        categoryMoveUndo = undo
    }
    func undoCategoryMove() throws {
        guard let undo = categoryMoveUndo else { return }
        var draft = ledger; try draft.undoCategoryMove(undo, writer: writer); try commit(draft)
        categoryMoveUndo = nil
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

    func categoryNames(for entry: CheckIn) -> String {
        let names = ledger.effectiveCategoryIDs(for: entry).map { ledger.categoryPath($0) }
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

    func setCaptureTiming(_ capture: Capture, timing: CaptureTiming?) throws {
        var draft = ledger; try draft.setCaptureTiming(capture.id, timing: timing, writer: writer); try commit(draft)
    }

    func reviewCapture(_ capture: Capture, text: String, categoryIDs: [String], notes: String? = nil) throws {
        var draft = ledger
        if let notes { try draft.updateCapture(id: capture.id, text: text, notes: notes, writer: writer) }
        else { try draft.updateCaptureText(id: capture.id, text: text, writer: writer) }
        try draft.categorizeCapture(id: capture.id, categoryIDs: categoryIDs, writer: writer)
        try commit(draft)
    }
    func categorizeCapture(_ capture: Capture, categoryIDs: [String]) throws {
        var draft = ledger
        try draft.categorizeCapture(id: capture.id, categoryIDs: categoryIDs, writer: writer)
        try commit(draft)
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

    @discardableResult
    func saveCategory(id: String?, name: String) throws -> String {
        var draft = ledger; try draft.saveCategory(id: id, name: name, writer: writer)
        let savedID = id ?? draft.categories.last!.id
        try commit(draft)
        return savedID
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
        try commitCategorization(draft)
    }

    func categorize(_ entry: CheckIn, categoryIDs: [String]) throws {
        var draft = ledger
        try draft.confirmCategories(for: entry.id, categoryIDs: categoryIDs, writer: writer)
        try commitCategorization(draft)
    }

    func categorize(_ entry: CheckIn, categoryIDs: [String], mood: Int?) throws {
        var draft = ledger
        try draft.confirmCategories(for: entry.id, categoryIDs: categoryIDs, writer: writer)
        try draft.setMood(for: entry.id, value: mood, writer: writer)
        try commitCategorization(draft)
    }

    func moveLogs(_ ids: Set<String>, from source: String, to destination: String) throws {
        var draft = ledger
        try draft.moveLogs(ids, from: source, to: destination, writer: writer)
        try commitCategorization(draft)
    }

    private func commitCategorization(_ draft: Ledger) throws {
        let changed = draft.entries.compactMap { updated -> (before: CheckIn, after: CheckIn)? in
            guard let original = ledger.entries.first(where: { $0.id == updated.id }),
                  original.categoryIDs != updated.categoryIDs || original.categoryID != updated.categoryID || original.categoryAssignment != updated.categoryAssignment || original.mood != updated.mood || original.goalID != updated.goalID || original.goalShare != updated.goalShare else { return nil }
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
                draft.entries[index].categorySuggestion = change.before.categorySuggestion
                draft.entries[index].mood = change.before.mood
                draft.entries[index].goalID = change.before.goalID
                draft.entries[index].goalShare = change.before.goalShare
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
        let rows = ledger.breakdown(on: ledger.reportingDay(containing: now), now: now).filter { $0.minutes > 0 }.sorted { $0.minutes > $1.minutes }
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
