import SwiftUI
import WatchKit

struct WatchQuickLogRequest: Identifiable {
    let id = "watch-complication-\(UUID().uuidString)"
}

struct WatchQuickLogView: View {
    @StateObject private var reply = WatchReplyState()
    let id: String
    let finish: () -> Void
    #if DEBUG
    @State private var fixtureInputOpen = false
    #endif

    var body: some View {
        content
            .task {
                reply.sampleID = id
                // A cold complication launch can arrive before the WatchKit
                // hosting controller is active. Wait for it, without another tap.
                for _ in 0..<20 {
                    guard !Task.isCancelled else { return }
                    if WKApplication.shared().applicationState == .active,
                       WKApplication.shared().visibleInterfaceController != nil {
                        dictate(); return
                    }
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
                reply.error = "Input is not ready yet. Tap Dictate log to try again."
            }
            .task(id: reply.saved) {
                guard reply.saved else { return }
                do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
                finish()
            }
    }

    @ViewBuilder private var content: some View {
        #if DEBUG
        if fixtureInputOpen {
            VStack(spacing: 8) {
                Text("Simulated dictation").font(.caption2)
                Text("Preparing classes").font(.caption)
                HStack {
                    Button("Done") { fixtureInputOpen = false; accept("Preparing classes") }
                        .accessibilityIdentifier("watch.fixture.done")
                    Button("Cancel") { fixtureInputOpen = false; accept(nil) }
                        .accessibilityIdentifier("watch.fixture.cancel")
                }
            }.padding(.horizontal, 8)
        } else {
            WatchPromptView(reply: reply, dictate: dictate)
        }
        #else
        WatchPromptView(reply: reply, dictate: dictate)
        #endif
    }

    private func dictate() {
        guard !reply.inputOpen, !reply.saved else { return }
        if reply.pendingText != nil { save(); return }
        reply.error = nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-watch-quick-log") {
            reply.inputOpen = true; fixtureInputOpen = true; return
        }
        #endif
        guard let controller = WKApplication.shared().visibleInterfaceController else {
            reply.error = "Input is not ready yet. Tap Dictate log to try again."; return
        }
        reply.inputOpen = true
        // Match notification replies: nil suggestions, plain system dictation,
        // and save only the accepted result, never partial transcript changes.
        controller.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
            accept(results?.first as? String)
        }
    }

    private func accept(_ text: String?) {
        reply.inputOpen = false
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { finish(); return }
        reply.pendingText = text; reply.responseTime = Date()
        save()
    }

    private func save() {
        guard let text = reply.pendingText, let timestamp = reply.responseTime else { return }
        do {
            try LedgerStore.shared.saveQuickSample(text, id: id, at: timestamp)
            reply.pendingText = nil; reply.saved = true; reply.error = nil
            WKInterfaceDevice.current().play(.success)
        } catch {
            // Keep text, ID and timestamp for an idempotent saving retry.
            reply.error = error.localizedDescription
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
