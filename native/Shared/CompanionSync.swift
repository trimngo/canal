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
        session?.delegate = self; session?.activate()
    }

    #if os(watchOS)
    func holdBackgroundTask(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        backgroundTasks.append(task)
        completeBackgroundTasksIfReady()
    }
    #endif

    private func completeBackgroundTasksIfReady() {
        #if os(watchOS)
        guard let session, session.activationState == .activated,
              !session.hasContentPending, incomingWrites.isIdle else { return }
        for task in backgroundTasks { task.setTaskCompletedWithSnapshot(false) }
        backgroundTasks.removeAll()
        #endif
    }
    func send() {
        guard let session, session.activationState == .activated, let store else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        do {
            let data = try JSONEncoder().encode(store.ledger)
            // A file transfer avoids WatchConnectivity's small message-size limit.
            // Keep only the newest outgoing snapshot; merge retains offline edits.
            for transfer in session.outstandingFileTransfers { transfer.cancel() }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-transfer-\(UUID().uuidString).json")
            try data.write(to: url, options: [.atomic])
            session.transferFile(url, metadata: ["schema": 2])
        } catch { store.report(error) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in
            if let error { self?.store?.report(error) } else { self?.send() }
            self?.completeBackgroundTasksIfReady()
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
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        if let error { Task { @MainActor [weak self] in self?.store?.report(error) } }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
