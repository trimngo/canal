import Foundation
import WatchConnectivity
import LedgerCore

@MainActor
final class CompanionSync: NSObject, WCSessionDelegate {
    private weak var store: LedgerStore?
    private let session: WCSession?
    init(store: LedgerStore) {
        self.store = store
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
    }

    func start() { session?.delegate = self; session?.activate() }
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
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The system deletes received files when this delegate returns.
        let result = Result { try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: file.fileURL)) }
        Task { @MainActor [weak self] in
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
