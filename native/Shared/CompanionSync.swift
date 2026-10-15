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
        retryTask?.cancel(); retryTask = nil; retry.reset()
        send()
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
        guard let session, let store, retryTask == nil else { return }
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
        // WatchConnectivity already queues delivery while the other device is
        // unreachable. Never cancel that queue on foreground, save, or merge.
        guard session.outstandingFileTransfers.isEmpty else {
            store.companionStatus = "Saved on this device · sync queued"
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
            store.companionStatus = "Saved on this device · sync queued"
        } catch {
            if let transferID { delivery.finish(id: transferID, succeeded: false) }
            if let temporaryFile { try? FileManager.default.removeItem(at: temporaryFile) }
            connectionFailed(error)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.activationRequested = false
            if let error { self.connectionFailed(error) }
            else if activationState == .activated { self.send() }
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
                self.store?.companionStatus = "Synced with paired device"
                self.send() // Include edits committed while the previous file was in flight.
            }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
