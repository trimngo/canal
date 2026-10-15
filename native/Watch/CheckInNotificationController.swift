import SwiftUI
import WatchKit
import UserNotifications

@MainActor
final class WatchReplyState: ObservableObject {
    @Published var inputOpen = false
    @Published var saved = false
    @Published var error: String?
    var pendingText: String?
    var responseTime: Date?
}

final class CheckInNotificationController: WKUserNotificationHostingController<WatchPromptView> {
    private let reply = WatchReplyState()
    private var deliveryID = ""
    override class var isInteractive: Bool { true }
    override var body: WatchPromptView {
        WatchPromptView(reply: reply) { [weak self] in self?.dictate() }
    }

    override func didReceive(_ notification: UNNotification) {
        // The custom input button replaces the action list. Viewing a prompt
        // must not open/reset the app's full sample editor.
        notificationActions = []
        deliveryID = NotificationScheduler.replyID(for: notification)
        reply.inputOpen = false; reply.saved = false; reply.error = nil
        reply.pendingText = nil; reply.responseTime = nil
        LedgerStore.shared.start()
    }

    private func dictate() {
        guard !reply.inputOpen, !reply.saved else { return }
        if reply.pendingText != nil { saveReply(); return }
        reply.inputOpen = true; reply.error = nil
        // The system owns dictation/keyboard presentation. The completion runs
        // after Done/Send, never on individual transcript changes.
        presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { [weak self] results in
            guard let self else { return }
            self.reply.inputOpen = false
            guard let text = results?.first as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.reply.pendingText = text
            self.reply.responseTime = Date()
            self.saveReply()
        }
    }

    private func saveReply() {
        guard let text = reply.pendingText, let timestamp = reply.responseTime else { return }
        do {
            try LedgerStore.shared.saveQuickSample(text, id: deliveryID, at: timestamp)
            reply.pendingText = nil; reply.saved = true; reply.error = nil
            WKInterfaceDevice.current().play(.success)
            let completed = deliveryID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self, self.deliveryID == completed else { return }
                self.performDismissAction()
            }
        } catch {
            // Keep accepted text and its response time for a saving retry.
            reply.error = error.localizedDescription
            WKInterfaceDevice.current().play(.failure)
        }
    }
}

struct WatchPromptView: View {
    @ObservedObject var reply: WatchReplyState
    var dictate: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            if reply.saved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.title3).foregroundStyle(.mint)
                    .accessibilityIdentifier("watch.reply.saved")
            } else {
                Text("What are you doing now?").font(.headline)
                Button(action: dictate) {
                    Label(reply.pendingText == nil ? "Dictate log" : "Retry saving", systemImage: reply.pendingText == nil ? "mic.fill" : "arrow.clockwise")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }.buttonStyle(.borderedProminent).disabled(reply.inputOpen)
                    .accessibilityIdentifier("watch.reply.dictate")
                if let error = reply.error {
                    Text("Not saved. \(error)").font(.caption).foregroundStyle(.red)
                }
            }
        }.padding(.vertical, 6)
    }
}
