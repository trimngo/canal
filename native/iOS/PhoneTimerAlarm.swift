import AlarmKit
import Combine
import SwiftUI
import UIKit
import LedgerCore

/// AlarmKit is an opt-in iPhone alert engine. The existing ActivityKit timer
/// remains the cross-device display; a fixed alarm avoids a second countdown.
@MainActor
final class PhoneTimerAlarm: ObservableObject {
    static let shared = PhoneTimerAlarm()
    @Published private(set) var status = ""
    private let recordKey = "timers.system-alarm.record"
    private let silencedKey = "timers.system-alarm.silenced"
    private var preparing: String?
    private var work: Task<Bool, Never>?
    private var generation = UUID()
    private var preparationBackgroundID = UIBackgroundTaskIdentifier.invalid
    private var preparationExpired = false
    enum PreparationError: Error { case busy }
    private struct Record: Codable {
        var id: UUID
        var token: String
        var title: String
        var dueAt: Date
    }
    private var record: Record? {
        get { UserDefaults.standard.data(forKey: recordKey).flatMap { try? JSONDecoder().decode(Record.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: recordKey) }
            else { UserDefaults.standard.removeObject(forKey: recordKey) }
        }
    }
    private var mock: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-alarmkit-available") ||
            ProcessInfo.processInfo.arguments.contains("--ui-alarmkit-fail") || mockDenied
        #else
        return false
        #endif
    }
    private var mockDenied: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-alarmkit-denied")
        #else
        return false
        #endif
    }
    var isSupported: Bool {
        if mock { return true }
        #if targetEnvironment(simulator)
        return false
        #else
        if #available(iOS 26.0, *) { return true }
        return false
        #endif
    }
    func requestPermission() async -> Bool {
        if mockDenied { status = "System alarms are not allowed · existing alerts stay enabled"; return false }
        if mock { return true }
        guard isSupported else { status = "System alarms require iOS 26 on an iPhone"; return false }
        if #available(iOS 26.0, *) {
            do {
                let allowed = try await AlarmManager.shared.requestAuthorization() == .authorized
                if !allowed { status = "System alarms are not allowed · existing alerts stay enabled" }
                return allowed
            } catch { status = "System alarm permission unavailable · existing alerts stay enabled" }
        }
        return false
    }
    private var authorized: Bool {
        if mockDenied { return false }
        if mock { return true }
        guard isSupported else { return false }
        if #available(iOS 26.0, *) { return AlarmManager.shared.authorizationState == .authorized }
        return false
    }
    func isSilenced(_ token: String) -> Bool { UserDefaults.standard.string(forKey: silencedKey) == token }
    func noteNotificationFallback(_ message: String, token: String) {
        let ledger = LedgerStore.shared.ledger
        guard ledger.timerControl?.token == token,
              PhoneTimerAlarmPolicy.schedulesSystemAlarm(ledger, writer: LedgerStore.shared.writer) else { return }
        status = "System alarm unavailable · " + message
    }

    /// Returns true only when AlarmKit owns this exact timer or the user stopped
    /// its alert. False leaves the existing one-time notification fallback.
    func refresh(_ ledger: Ledger, writer: String) async -> Bool {
        guard preparing == nil else { return false }
        let previous = work, id = UUID(); generation = id
        let task = Task { @MainActor in
            _ = await previous?.value
            guard self.preparing == nil,
                  ledger.timerControl == LedgerStore.shared.ledger.timerControl,
                  ledger.currentTimer == LedgerStore.shared.ledger.currentTimer,
                  ledger.settings.timerSystemAlarms == LedgerStore.shared.ledger.settings.timerSystemAlarms else { return false }
            return await self.apply(ledger, writer: writer)
        }
        work = task; let result = await task.value
        if generation == id { work = nil }
        return result
    }

    /// Keep normal refreshes from cancelling a staged alarm before the atomic
    /// ledger commit. The caller must finish/abandon preparation on every path.
    func prepare(_ ledger: Ledger, writer: String) async throws -> Bool {
        guard preparing == nil, let token = ledger.timerControl?.token else { throw PreparationError.busy }
        preparing = token
        preparationExpired = false
        preparationBackgroundID = UIApplication.shared.beginBackgroundTask(withName: "Timer alarm handover") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.preparationExpired = true
                if self.preparationBackgroundID != .invalid { UIApplication.shared.endBackgroundTask(self.preparationBackgroundID) }
                self.preparationBackgroundID = .invalid
            }
        }
        _ = await work?.value
        return await apply(ledger, writer: writer)
    }
    func preparationIsValid(_ token: String) -> Bool { preparing == token && !preparationExpired }
    func finishPreparation(_ token: String) {
        guard preparing == token else { return }
        preparing = nil
        if preparationBackgroundID != .invalid { UIApplication.shared.endBackgroundTask(preparationBackgroundID) }
        preparationBackgroundID = .invalid
    }
    func abandonPreparation(_ token: String) async {
        if record?.token == token { _ = await cancelRecord() }
        finishPreparation(token)
    }
    private func apply(_ ledger: Ledger, writer: String) async -> Bool {
        guard PhoneTimerAlarmPolicy.schedulesSystemAlarm(ledger, writer: writer),
              let timer = ledger.currentTimer, let control = ledger.timerControl, let due = control.dueAt else {
            let cancelled = await cancelRecord()
            if cancelled { status = "" }
            return false
        }
        if isSilenced(control.token) {
            status = "System alarm silenced · timer awaits Done or Restart"; return true
        }
        guard authorized else {
            _ = await cancelRecord()
            status = "System alarm unavailable"
            return false
        }
        do {
            if let old = record, old.token == control.token, old.title == timer.title, old.dueAt == due {
                if mock { status = "iPhone system alarm scheduled"; return true }
                if #available(iOS 26.0, *), try AlarmManager.shared.alarms.contains(where: { $0.id == old.id }) {
                    status = "iPhone system alarm scheduled"; return true
                }
                // Once a scheduled alarm has disappeared at/after its deadline,
                // reopening must not recreate it or turn user Stop into an alert.
                if due <= Date() {
                    UserDefaults.standard.set(control.token, forKey: silencedKey)
                    status = "System alarm ended · timer awaits Done or Restart"; return true
                }
            }
            guard await cancelRecord() else { return false }
            guard due > Date() else { status = "Timer finished"; return false }
            let next = Record(id: UUID(), token: control.token, title: timer.title, dueAt: due)
            // Persist the identity before scheduling so relaunch can cancel or
            // adopt an alarm even if the process exits around the API call.
            record = next
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-alarmkit-fail") {
                record = nil; status = "System alarm unavailable"; return false
            }
            #endif
            if !mock {
                if #available(iOS 26.0, *) { try await schedule(next) }
                else { record = nil; return false }
            }
            status = "iPhone system alarm scheduled"
            return true
        } catch {
            // Preserve an uncertain record until cancellation is confirmed.
            _ = await cancelRecord()
            status = "System alarm unavailable"
            return false
        }
    }
    private func cancelRecord() async -> Bool {
        guard let old = record else { return true }
        do {
            if !mock, isSupported, #available(iOS 26.0, *), try AlarmManager.shared.alarms.contains(where: { $0.id == old.id }) {
                try AlarmManager.shared.cancel(id: old.id)
            }
            record = nil; return true
        } catch {
            status = "Previous iPhone alarm cancellation pending · open Dash to retry"
            return false
        }
    }
    func silence(_ token: String) async {
        guard LedgerStore.shared.ledger.timerControl?.token == token else { return }
        UserDefaults.standard.set(token, forKey: silencedKey)
        if record?.token == token { _ = await cancelRecord() }
        status = "System alarm silenced · timer awaits Done or Restart"
    }
    @available(iOS 26.0, *)
    private func schedule(_ next: Record) async throws {
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: next.title),
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"),
            secondaryButton: AlarmButton(text: "Restart", textColor: .white, systemImageName: "arrow.clockwise"),
            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes<DashAlarmMetadata>(presentation: AlarmPresentation(alert: alert),
            metadata: DashAlarmMetadata(token: next.token), tintColor: .mint)
        let configuration = AlarmManager.AlarmConfiguration<DashAlarmMetadata>.alarm(
            schedule: .fixed(next.dueAt), attributes: attributes,
            stopIntent: SilenceTimerAlarmIntent(token: next.token), secondaryIntent: RestartTimerIntent(token: next.token))
        _ = try await AlarmManager.shared.schedule(id: next.id, configuration: configuration)
    }
}

@available(iOS 26.0, *)
private struct DashAlarmMetadata: AlarmMetadata { var token: String }
