import Foundation

public enum TimerQueueError: LocalizedError {
    case invalidTask, invalidDuration, missingDuration
    public var errorDescription: String? {
        switch self {
        case .invalidTask: return "Give this timer a task name (up to 500 characters)."
        case .invalidDuration: return "Choose a duration between one second and 24 hours."
        case .missingDuration: return "Include a duration, for example: Practice guitar for twenty minutes."
        }
    }
}

public struct QueuedTimer: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var duration: TimeInterval
    public var createdAt: Date
    public var completedAt: Date?
    public var deletedAt: Date?
    public var revision: Revision
    public init(id: String = UUID().uuidString, title: String, duration: TimeInterval, createdAt: Date = Date(), revision: Revision = Revision()) {
        self.id = id; self.title = title; self.duration = duration; self.createdAt = createdAt; self.revision = revision
    }
}

/// A single control record prevents two queued tasks from running together.
/// Absolute deadlines survive suspension; expiry never advances the queue.
public struct TimerQueueControl: Codable, Equatable, Sendable {
    public var taskID: String?
    public var dueAt: Date?
    public var pausedRemaining: TimeInterval?
    public var owner: String
    public var onWatch: Bool
    public var revision: Revision
    public var token: String { "task-timer-\(revision.writer)-\(revision.counter)" }
    public init(taskID: String?, dueAt: Date?, pausedRemaining: TimeInterval? = nil, owner: String, onWatch: Bool, revision: Revision) {
        self.taskID = taskID; self.dueAt = dueAt; self.pausedRemaining = pausedRemaining
        self.owner = owner; self.onWatch = onWatch; self.revision = revision
    }
    public func remaining(at now: Date) -> TimeInterval { max(0, pausedRemaining ?? dueAt?.timeIntervalSince(now) ?? 0) }
    public func isFinished(at now: Date) -> Bool { pausedRemaining == nil && dueAt.map { $0 <= now } == true }
}

public struct TimerWidgetSnapshot: Codable, Equatable, Sendable {
    public var title: String
    public var duration: Double
    public var dueAt: Date?
    public var pausedRemaining: TimeInterval?
    public init(title: String, duration: Double, dueAt: Date?, pausedRemaining: TimeInterval?) {
        self.title = title; self.duration = duration; self.dueAt = dueAt; self.pausedRemaining = pausedRemaining
    }
}

public enum TimerQueueShortcut {
    public static let add = URL(string: "canal-dash://queue-timer")!
    public static let current = URL(string: "canal-dash://timers")!
    public static func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "canal-dash" && ["queue-timer", "timers"].contains(url.host?.lowercased() ?? "") &&
        ["", "/"].contains(url.path) && url.query == nil && url.fragment == nil && url.user == nil && url.password == nil && url.port == nil
    }
}

/// Explicit durations only. Unparseable dictation remains a draft for correction.
public struct TimerDraft: Equatable, Sendable {
    public let title: String
    public let duration: TimeInterval
    public static func parse(_ text: String) throws -> TimerDraft {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, original.count <= 600 else { throw TimerQueueError.invalidTask }
        let words = ["zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
                     "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
                     "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "ninety": 90]
        // Normalize number words only in the duration portion; preserve the task.
        let splitter = try NSRegularExpression(pattern: "(?i)\\s+(?:for|,)\\s*|,\\s*")
        let parts = splitter.matches(in: original, range: NSRange(original.startIndex..., in: original))
        var candidates: [(String, String)] = []
        for match in parts.reversed() {
            guard let range = Range(match.range, in: original) else { continue }
            candidates.append((String(original[..<range.lowerBound]), String(original[range.upperBound...])))
        }
        // Also accept a duration first: “20 minutes practice guitar”.
        let durationPattern = "(?i)^((?:(?:[0-9.]+|[a-z]+)(?:[- ][a-z]+)?\\s*(?:hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\\s*(?:and\\s*)?)+)\\s+(.+)$"
        if let regex = try? NSRegularExpression(pattern: durationPattern), let match = regex.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)),
           let durationRange = Range(match.range(at: 1), in: original), let titleRange = Range(match.range(at: 2), in: original) {
            candidates.append((String(original[titleRange]), String(original[durationRange])))
        }
        for (title, raw) in candidates {
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;")))
            guard !cleanTitle.isEmpty, cleanTitle.count <= 500 else { continue }
            var durationText = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;")))
            if durationText.range(of: "(?:^|\\s)-\\s*[0-9]", options: .regularExpression) != nil { throw TimerQueueError.invalidDuration }
            durationText = durationText.replacingOccurrences(of: "-", with: " ")
            durationText = durationText.replacingOccurrences(of: "half an hour", with: "30 minutes").replacingOccurrences(of: "an hour", with: "1 hour").replacingOccurrences(of: "a minute", with: "1 minute")
            let numberPattern = "\\b(?:" + words.keys.sorted { $0.count > $1.count }.joined(separator: "|") + ")(?:\\s+(?:one|two|three|four|five|six|seven|eight|nine))?\\b"
            let numberRegex = try NSRegularExpression(pattern: numberPattern)
            for match in numberRegex.matches(in: durationText, range: NSRange(durationText.startIndex..., in: durationText)).reversed() {
                guard let range = Range(match.range, in: durationText) else { continue }
                let value = durationText[range].split(separator: " ").reduce(0) { $0 + (words[String($1)] ?? 0) }
                durationText.replaceSubrange(range, with: String(value))
            }
            let regex = try NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)\\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\\b")
            let matches = regex.matches(in: durationText, range: NSRange(durationText.startIndex..., in: durationText))
            var seconds = 0.0
            for match in matches {
                guard let n = Range(match.range(at: 1), in: durationText), let u = Range(match.range(at: 2), in: durationText), let value = Double(durationText[n]) else { continue }
                let unit = durationText[u]
                seconds += value * (unit.hasPrefix("h") ? 3600 : unit.hasPrefix("m") ? 60 : 1)
            }
            let leftover = regex.stringByReplacingMatches(in: durationText, range: NSRange(durationText.startIndex..., in: durationText), withTemplate: "")
                .replacingOccurrences(of: "and", with: "").trimmingCharacters(in: .whitespaces)
            guard !matches.isEmpty, leftover.isEmpty else { continue }
            guard seconds.isFinite, (1...86400).contains(seconds) else { throw TimerQueueError.invalidDuration }
            return TimerDraft(title: cleanTitle, duration: seconds)
        }
        throw TimerQueueError.missingDuration
    }
}

extension Ledger {
    public var currentTimer: QueuedTimer? {
        guard let id = timerControl?.taskID else { return nil }
        return queuedTimers?.first { $0.id == id && $0.completedAt == nil && $0.deletedAt == nil }
    }
    public var waitingTimers: [QueuedTimer] {
        (queuedTimers ?? []).filter { $0.completedAt == nil && $0.deletedAt == nil && $0.id != currentTimer?.id }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
    }
    public mutating func enqueueTimer(id: String = UUID().uuidString, title: String, duration: TimeInterval, writer: String, onWatch: Bool, now: Date = Date()) throws {
        guard queuedTimers?.contains(where: { $0.id == id }) != true else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 500 else { throw TimerQueueError.invalidTask }
        guard duration.isFinite, (1...86400).contains(duration) else { throw TimerQueueError.invalidDuration }
        let value = QueuedTimer(id: id, title: title, duration: duration, createdAt: now, revision: nextRevision(writer: writer))
        queuedTimers = (queuedTimers ?? []) + [value]
        if currentTimer == nil, timerControl?.taskID == nil { startNextTimer(writer: writer, onWatch: onWatch, now: now) }
    }
    public mutating func startNextTimer(writer: String, onWatch: Bool, now: Date = Date()) {
        guard currentTimer == nil else { return }
        let next = waitingTimers.first
        timerControl = TimerQueueControl(taskID: next?.id, dueAt: next.map { now.addingTimeInterval($0.duration) }, owner: writer, onWatch: onWatch, revision: nextRevision(writer: writer))
    }
    public mutating func finishTimer(expectedToken: String? = nil, writer: String, onWatch: Bool, now: Date = Date()) {
        guard let current = currentTimer, expectedToken == nil || timerControl?.token == expectedToken,
              let i = queuedTimers?.firstIndex(where: { $0.id == current.id }) else { return }
        queuedTimers?[i].completedAt = now
        let revision = nextRevision(writer: writer); queuedTimers?[i].revision = revision
        startNextTimer(writer: writer, onWatch: onWatch, now: now)
    }
    public mutating func restartTimer(expectedToken: String? = nil, writer: String, onWatch: Bool, now: Date = Date()) {
        guard let task = currentTimer, expectedToken == nil || timerControl?.token == expectedToken else { return }
        timerControl = TimerQueueControl(taskID: task.id, dueAt: now.addingTimeInterval(task.duration), owner: writer, onWatch: onWatch, revision: nextRevision(writer: writer))
    }
    public mutating func pauseTimer(writer: String, onWatch: Bool, now: Date = Date()) {
        guard let task = currentTimer, let control = timerControl, control.pausedRemaining == nil, !control.isFinished(at: now) else { return }
        timerControl = TimerQueueControl(taskID: task.id, dueAt: nil, pausedRemaining: control.remaining(at: now), owner: writer, onWatch: onWatch, revision: nextRevision(writer: writer))
    }
    public mutating func resumeTimer(writer: String, onWatch: Bool, now: Date = Date()) {
        guard let task = currentTimer, let remaining = timerControl?.pausedRemaining else { return }
        timerControl = TimerQueueControl(taskID: task.id, dueAt: now.addingTimeInterval(remaining), owner: writer, onWatch: onWatch, revision: nextRevision(writer: writer))
    }
    public mutating func moveTimerAlerts(writer: String, onWatch: Bool) {
        guard currentTimer != nil, var control = timerControl else { return }
        control.owner = writer; control.onWatch = onWatch; control.revision = nextRevision(writer: writer); timerControl = control
    }
    public mutating func deleteQueuedTimer(_ id: String, writer: String, onWatch: Bool, now: Date = Date()) {
        guard let i = queuedTimers?.firstIndex(where: { $0.id == id }), queuedTimers?[i].deletedAt == nil else { return }
        let wasCurrent = currentTimer?.id == id
        let revision = nextRevision(writer: writer)
        queuedTimers?[i].deletedAt = now; queuedTimers?[i].revision = revision
        if wasCurrent { startNextTimer(writer: writer, onWatch: onWatch, now: now) }
    }
}
