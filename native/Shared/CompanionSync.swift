import Foundation
import WatchConnectivity
import LedgerCore
#if os(watchOS)
import WatchKit
#endif

private final class CompanionWriteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func begin() { lock.lock(); defer { lock.unlock() }; count += 1 }
    func end() { lock.lock(); defer { lock.unlock() }; count -= 1 }
    var isIdle: Bool { lock.lock(); defer { lock.unlock() }; return count == 0 }
}

@MainActor
final class CompanionSync: NSObject, WCSessionDelegate {
    private weak var store: LedgerStore?
    private let session: WCSession?
    private var activationRequested = false
    private var delivery = CompanionDeliveryState()
    private var quick = CompanionQuickDelivery()
    private var quickID: String?
    private var quickTimeout: Task<Void, Never>?
    private var quickRetry = CompanionRetry()
    private var quickRetryTask: Task<Void, Never>?
    private var retry = CompanionRetry()
    private var retryTask: Task<Void, Never>?
    nonisolated private let incomingWrites = CompanionWriteCounter()
    #if os(watchOS)
    private var backgroundTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var pendingObservation: NSKeyValueObservation?
    #endif
    init(store: LedgerStore) {
        self.store = store
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
    }

    func start() {
        #if os(watchOS)
        pendingObservation = session?.observe(\.hasContentPending, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.completeBackgroundTasksIfReady() }
        }
        #endif
        session?.delegate = self
        send()
    }

    func refresh() {
        if let context = session?.receivedApplicationContext { receiveSettings(context) }
        retryTask?.cancel(); retryTask = nil; retry.reset()
        quickRetryTask?.cancel(); quickRetryTask = nil; quickRetry.reset()
        send()
    }

    func hasReceivedSample(_ entry: CheckIn) -> Bool { quick.hasReceived(entry) }

    private func sendSettings() {
        guard let session, let settings = store?.ledger.settings, settings.revision > Revision() else { return }
        // Application context keeps only the newest small settings snapshot,
        // independently of queued history files, even when the peer is asleep.
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(settings)
            if session.applicationContext["settings"] as? Data != data {
                try session.updateApplicationContext(["settings": data])
            }
        } catch { /* The acknowledged fast lane and full-file queue also retry. */ }
    }

    private func receiveSettings(_ context: [String: Any]) {
        guard let data = context["settings"] as? Data else { return }
        do {
            var partial = Ledger(); partial.categories = []
            partial.settings = try JSONDecoder().decode(Settings.self, from: data)
            try store?.merge(partial)
        } catch { /* Keep the saved local copy; the other sync paths retry. */ }
    }

    private var queuedStatus: String {
        guard let store else { return "Sync queued" }
        #if os(watchOS)
        return quick.recentLogsReceived(in: store.ledger) ? "Recent logs received by iPhone" : "Saved on Watch · waiting for iPhone"
        #else
        return quick.recentLogsReceived(in: store.ledger) ? "Recent logs received by Watch" : "Saved on iPhone · sync queued"
        #endif
    }

    private func sendQuickly() {
        guard let session, session.isReachable, let store, quickRetryTask == nil else { return }
        let id = UUID().uuidString
        do {
            guard let data = try quick.prepare(store.ledger, id: id) else { return }
            quickID = id
            session.sendMessageData(data, replyHandler: { [weak self] response in
                let receipt = try? JSONDecoder().decode(CompanionQuickReceipt.self, from: response)
                Task { @MainActor in
                    guard let self, self.quickID == id else { return }
                    guard let receipt, receipt.id == id, receipt.saved else { self.quickFailed(id); return }
                    self.quickTimeout?.cancel(); self.quickTimeout = nil; self.quickID = nil
                    self.quick.finish(id: id, saved: true)
                    self.quickRetry.reset(); self.store?.companionDiagnostic = nil
                    self.store?.companionStatus = self.queuedStatus
                    self.send() // Pick up responses saved while this receipt was in flight.
                }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in self?.quickFailed(id) }
            })
            quickTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                self?.quickFailed(id)
            }
        } catch { store.companionStatus = queuedStatus }
    }

    private func quickFailed(_ id: String) {
        guard quickID == id else { return }
        quickTimeout?.cancel(); quickTimeout = nil; quickID = nil
        quick.finish(id: id, saved: false)
        store?.companionStatus = queuedStatus
        // Background file delivery remains queued even if immediate delivery fails.
        guard quickRetryTask == nil, let delay = quickRetry.nextDelay() else { return }
        quickRetryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) } catch { return }
            self?.quickRetryTask = nil; self?.send()
        }
    }

    private func connectionFailed(_ error: Error) {
        // Transport/XPC failures do not invalidate a successful local commit.
        // Keep only domain/code for diagnosis, never activity text or file paths.
        let detail = error as NSError
        store?.companionDiagnostic = "\(detail.domain) (\(detail.code))"
        store?.companionStatus = "Saved on this device · sync waiting"
        guard retryTask == nil, let delay = retry.nextDelay() else { return }
        retryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) }
            catch { return }
            guard let self else { return }
            self.retryTask = nil
            self.send()
        }
    }

    #if os(watchOS)
    func holdBackgroundTask(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        backgroundTasks.append(task)
        completeBackgroundTasksIfReady()
    }
    #endif

    private func completeBackgroundTasksIfReady(activationFailed: Bool = false) {
        #if os(watchOS)
        guard let session, incomingWrites.isIdle,
              activationFailed || (session.activationState == .activated && !session.hasContentPending) else { return }
        for task in backgroundTasks { task.setTaskCompletedWithSnapshot(false) }
        backgroundTasks.removeAll()
        #endif
    }
    func send() {
        guard let session, let store else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-companion-unavailable") {
            connectionFailed(NSError(domain: NSCocoaErrorDomain, code: 4099))
            return
        }
        #endif
        guard session.activationState == .activated else {
            guard !activationRequested else { return }
            activationRequested = true
            store.companionStatus = "Connecting to paired device…"
            session.activate()
            return
        }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else {
            store.companionStatus = "Saved on this device · Watch app not connected"
            return
        }
        #endif
        // Unlike file transfers, a reachable Watch can wake its paired iPhone
        // for an interactive message. Never wait behind an older history file.
        sendSettings()
        sendQuickly()
        guard retryTask == nil else { return }
        // WatchConnectivity already queues delivery while the other device is
        // unreachable. Never cancel that queue on foreground, save, or merge.
        guard session.outstandingFileTransfers.isEmpty else {
            store.companionStatus = queuedStatus
            return
        }
        var transferID: String?
        var temporaryFile: URL?
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(store.ledger)
            let id = UUID().uuidString
            guard delivery.begin(data, id: id) else { return }
            transferID = id
            // A file transfer avoids WatchConnectivity's small message-size limit.
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-transfer-\(UUID().uuidString).json")
            temporaryFile = url
            try data.write(to: url, options: [.atomic])
            session.transferFile(url, metadata: ["schema": 2, "transferID": id])
            store.companionStatus = queuedStatus
        } catch {
            if let transferID { delivery.finish(id: transferID, succeeded: false) }
            if let temporaryFile { try? FileManager.default.removeItem(at: temporaryFile) }
            connectionFailed(error)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.quickRetryTask?.cancel(); self.quickRetryTask = nil; self.quickRetry.reset()
            self.send()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Read the payload before leaving the delegate callback, as with files.
        guard let data = applicationContext["settings"] as? Data else { return }
        incomingWrites.begin()
        let writes = incomingWrites
        Task { @MainActor [weak self] in
            defer { writes.end(); self?.completeBackgroundTasksIfReady() }
            self?.receiveSettings(["settings": data])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData data: Data, replyHandler: @escaping (Data) -> Void) {
        incomingWrites.begin()
        let result = Result { try JSONDecoder().decode(CompanionQuickPacket.self, from: data) }
        let writes = incomingWrites
        Task { @MainActor [weak self] in
            defer { writes.end(); self?.completeBackgroundTasksIfReady() }
            var receipt = CompanionQuickReceipt(id: "", saved: false)
            do {
                let packet = try result.get(); receipt.id = packet.id
                guard let store = self?.store else { replyHandler(Data()); return }
                try store.merge(packet.ledger) // Atomic disk commit precedes the receipt.
                receipt.saved = true
            } catch { /* Sender retains its local save and background fallback. */ }
            replyHandler((try? JSONEncoder().encode(receipt)) ?? Data())
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.activationRequested = false
            if let error { self.connectionFailed(error) }
            else if activationState == .activated {
                self.receiveSettings(session.receivedApplicationContext)
                self.send()
            }
            else { self.connectionFailed(WCError(.sessionNotActivated)) }
            self.completeBackgroundTasksIfReady(activationFailed: error != nil || activationState != .activated)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The system deletes received files when this delegate returns.
        incomingWrites.begin()
        let result = Result { try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file.fileURL)) }
        let writes = incomingWrites
        Task { @MainActor [weak self] in
            defer { writes.end(); self?.completeBackgroundTasksIfReady() }
            do {
                guard let store = self?.store else { return }
                try store.merge(result.get())
                #if os(iOS)
                try await NotificationScheduler.shared.apply(store.ledger.settings)
                #endif
            } catch { self?.store?.report(error) }
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let id = fileTransfer.file.metadata?["transferID"] as? String
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let id { self.delivery.finish(id: id, succeeded: error == nil) }
            if let error { self.connectionFailed(error) }
            else {
                self.retryTask?.cancel(); self.retryTask = nil; self.retry.reset()
                self.store?.companionDiagnostic = nil
                // File handoff alone does not acknowledge an app-level save.
                self.store?.companionStatus = self.queuedStatus
                self.send() // Include edits committed while the previous file was in flight.
            }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
