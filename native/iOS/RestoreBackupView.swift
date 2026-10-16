import SwiftUI
import UniformTypeIdentifiers
import LedgerCore

struct RestoreBackupView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var files: [BackupFile] = []
    @State private var importing = false
    @State private var selected: LedgerBackup?
    @State private var data: Data?
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        List {
            if let selected {
                Section("Selected backup") {
                    Text(selected.savedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("\(selected.ledger.activeEntries.count) activity logs · \(selected.ledger.captures.filter { $0.deletedAt == nil }.count) ideas")
                    Button("Restore these records") {
                        guard let data else { return }
                        do {
                            try store.restoreBackup(data)
                            self.selected = nil; self.data = nil; message = "Restored. Your newer edits and existing logs were kept."
                        } catch { message = error.localizedDescription }
                    }.accessibilityIdentifier("backup.confirm-restore")
                }
            }
            Section {
                if busy { ProgressView("Opening backups…") }
                ForEach(files) { file in
                    Button {
                        Task { await open(file.url) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(file.modified == .distantPast ? "iCloud backup" : file.modified.formatted(date: .abbreviated, time: .shortened))
                            Text("Daily Dash backup").font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("backup.file")
                }
                Button("Refresh backup list") { Task { await refresh() } }
                Button("Choose a backup file…") { importing = true }.accessibilityIdentifier("backup.import")
            } header: { Text("iCloud Drive copies") } footer: {
                Text("Restoring adds missing records and keeps newer changes, including deletions. A copy of your current local data is saved before restoring. You can also choose a previously exported JSON backup.")
            }
            if let message { Section { Text(message).font(.footnote).accessibilityIdentifier("backup.message") } }
        }.navigationTitle("Restore backup").navigationBarTitleDisplayMode(.inline)
            .task { await refresh() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): Task { await open(url) }
                case .failure(let error): message = error.localizedDescription
                }
            }
    }
    private func refresh() async {
        busy = true; defer { busy = false }
        do { files = try await store.backup?.available() ?? []; message = files.isEmpty ? "No backups found yet. You can choose an exported file below." : nil }
        catch { message = error.localizedDescription }
    }
    private func open(_ url: URL) async {
        busy = true; defer { busy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let backup = store.backup else { return }
            let bytes = try await backup.read(url)
            selected = try LedgerBackup.decode(bytes); data = bytes; message = nil
        } catch { message = error.localizedDescription }
    }
}
