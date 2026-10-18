import Foundation
import LedgerCore
import UIKit

struct BackupFile: Identifiable, Sendable {
    let url: URL
    let modified: Date
    var id: String { url.absoluteString }
}

/// The phone backs up its full ledger, including observations received from the
/// Watch. iCloud Drive handles uploads while Ledger is suspended. Separate
/// device/day filenames prevent a fresh installation overwriting older history.
@MainActor
final class AutomaticBackup {
    private weak var store: LedgerStore?
    private let writer: String
    private var requested: Ledger?
    private var task: Task<Void, Never>?
    private var lastWritten: Data?
    private var lastURL: URL?
    private var uploadCheck: Task<Void, Never>?
    init(store: LedgerStore, writer: String) { self.store = store; self.writer = writer }

    func request(_ ledger: Ledger) {
        requested = ledger
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            let background = UIApplication.shared.beginBackgroundTask(withName: "Ledger backup") { [weak self] in
                Task { @MainActor in self?.task?.cancel() }
            }
            defer {
                if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
                self.task = nil
            }
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            while let ledger = self.requested {
                self.requested = nil
                do {
                    let previous = self.lastWritten, existingURL = self.lastURL, writer = self.writer
                    // Encoding a growing log history is background work too,
                    // not just writing its bytes. Keep ranking taps responsive.
                    let result = try await Task.detached(priority: .utility) {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                        let payload = try encoder.encode(ledger)
                        let url: URL
                        if payload != previous || existingURL == nil {
                            url = try Self.write(LedgerBackup(ledger: ledger).encoded(), writer: writer)
                        } else { url = existingURL! }
                        return (payload, url)
                    }.value
                    self.lastWritten = result.0; self.lastURL = result.1
                    if let url = self.lastURL {
                        self.updateUploadStatus(url)
                        self.pollUpload(url)
                    }
                } catch { self.store?.backupStatus = "Backup waiting · \(error.localizedDescription)" }
            }
        }
    }

    private func pollUpload(_ url: URL) {
        uploadCheck?.cancel()
        uploadCheck = Task { [weak self] in
            for _ in 0..<6 {
                do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                guard let self else { return }
                self.updateUploadStatus(url)
                let uploaded = try? url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey]).ubiquitousItemIsUploaded
                if uploaded == true { return }
            }
        }
    }

    private func updateUploadStatus(_ url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey, .contentModificationDateKey])
            if let error = values.ubiquitousItemUploadingError { throw error }
            let stamp = (values.contentModificationDate ?? Date()).formatted(date: .abbreviated, time: .shortened)
            store?.backupStatus = values.ubiquitousItemIsUploaded == true
                ? "Backed up to iCloud Drive · \(stamp)"
                : "Backup saved in iCloud Drive · upload pending"
        } catch { store?.backupStatus = "Backup saved locally · iCloud upload waiting" }
    }

    nonisolated private static func directory() throws -> URL {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-local-backup") {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("UITestBackups")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
        #endif
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.trimngo.TimeLedger") else { throw BackupFailure.iCloudUnavailable }
        let directory = root.appendingPathComponent("Documents/Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated private static func write(_ data: Data, writer: String) throws -> URL {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let url = try directory().appendingPathComponent("Ledger-\(formatter.string(from: Date()))-\(writer).json")
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { destination in
            do { try data.write(to: destination, options: [.atomic]) } catch { writeError = error }
        }
        if let error = writeError ?? coordinationError { throw error }
        return url
    }

    func available() async throws -> [BackupFile] {
        try await Task.detached(priority: .utility) {
            let directory = try Self.directory()
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
                .compactMap { url -> BackupFile? in
                    var candidate = url
                    if url.lastPathComponent.hasSuffix(".json.icloud") {
                        let name = String(url.lastPathComponent.dropFirst().dropLast(7))
                        candidate = url.deletingLastPathComponent().appendingPathComponent(name)
                    }
                    guard candidate.pathExtension == "json" else { return nil }
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    return BackupFile(url: candidate, modified: values?.contentModificationDate ?? .distantPast)
                }.sorted { $0.modified > $1.modified }
        }.value
    }

    func read(_ url: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            if values?.isUbiquitousItem == true, values?.ubiquitousItemDownloadingStatus == .notDownloaded {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
                throw BackupFailure.downloading
            }
            var coordinationError: NSError?
            var result: Result<Data, Error>?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
                result = Result { try Data(contentsOf: source) }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw BackupFailure.unreadable }
            return try result.get()
        }.value
    }

    enum BackupFailure: LocalizedError {
        case iCloudUnavailable, downloading, unreadable
        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable: return "Enable iCloud Drive for Dash in iPhone Settings."
            case .downloading: return "The backup is downloading from iCloud. Try opening it again shortly."
            case .unreadable: return "The backup could not be read."
            }
        }
    }
}
