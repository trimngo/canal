import SwiftUI

struct QuickLogCaptureView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var activity = ""
    @State private var saved = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                if saved {
                    Spacer()
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.largeTitle).foregroundStyle(.tint).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("quicklog.saved")
                    Spacer()
                } else {
                    Text("What are you doing now?").font(.title2.bold())
                    TextField("Type or dictate…", text: $activity, axis: .vertical)
                        .font(.title3).lineLimit(2...6).focused($focused).submitLabel(.send)
                        .accessibilityIdentifier("quicklog.activity").onSubmit(save)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button("Save log", action: save).font(.headline).frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.storageAvailable)
                        .accessibilityIdentifier("quicklog.save")
                    Spacer()
                }
            }.padding(24).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .task {
                    activity = store.quickReplyDraft ?? ""; store.quickReplyDraft = nil
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    focused = true
                }
        }
    }
    private func save() {
        guard !saved else { return }
        do {
            try store.saveQuickSample(activity, id: store.sampleRequestID.uuidString, at: Date())
            focused = false; saved = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Task { try? await Task.sleep(nanoseconds: 900_000_000); dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
