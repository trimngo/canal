import SwiftUI
import LedgerCore

struct LogTextEditView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let entry: CheckIn
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text).focused($focused)
                    .padding(8).scrollContentBackground(.hidden)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Log text").accessibilityIdentifier("log-text.field")
                if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("log-text.error") }
                Text("\(text.count)/500").font(.caption).foregroundStyle(text.count > 500 ? Color.red : Color.secondary)
            }.padding()
                .navigationTitle("Edit log text").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.accessibilityIdentifier("log-text.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                try store.updateLogActivity(id: entry.id, activity: text)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 500 || !store.storageAvailable)
                            .accessibilityIdentifier("log-text.save")
                    }
                }
        }.onAppear { text = entry.activity; focused = true }
            .onDisappear { focused = false }
    }
}
