#if DEBUG
import ActivityKit
import SwiftUI
import WatchConnectivity
import LedgerCore

/// Diagnostic branch only: real receiver, disk commit, and ActivityKit calls.
/// It bypasses radio transport and cannot establish physical background wake.
struct WatchRestartReproductionView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var receiptCount = 0
    @State private var result = "Not run"
    @State private var busy = false

    var body: some View {
        VStack(spacing: 8) {
            Text(store.ledger.timerControl?.isFinished(at: Date()) == true ? "Expired Watch timer" : "Running Watch timer")
                .accessibilityIdentifier("repro.timer-state")
            Text(store.ledger.timerControl?.onWatch == true ? "Watch alerts" : "Phone alerts")
                .accessibilityIdentifier("repro.owner")
            Text(result).accessibilityIdentifier("repro.result")
            Button("Receive Watch restart") {
                busy = true
                Task { @MainActor in
                    defer { busy = false }
                    do {
                        try await receiveRestart()
                        receiptCount += 1
                        result = "Saved receipt \(receiptCount)"
                    } catch { result = "Reproduction failed" }
                }
            }.disabled(busy).accessibilityIdentifier("repro.restart")
        }.padding().frame(maxWidth: .infinity).background(.regularMaterial)
    }

    @MainActor private func receiveRestart() async throws {
        guard ProcessInfo.processInfo.arguments.contains("--ui-watch-restart-repro") else { throw ReproductionError.disabled }
        let receiver = CompanionSync(store: store)
        let before = store.ledger
        var watch = before
        watch.restartTimer(writer: "paired-watch", onWatch: true)
        guard let token = watch.timerControl?.token,
              let data = try CompanionQuickDelivery.timerSnapshot(watch),
              let older = try CompanionQuickDelivery.timerSnapshot(before) else { throw ReproductionError.payload }
        // Establish the same existing Live Activity that a real phone mirrors.
        await TimerLiveActivity.shared.refresh(store.ledger)
        let activityBefore = Activity<TimerLiveAttributes>.activities.first
        let saved: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                receiver.session(WCSession.default, didReceiveMessageData: data) { response in
                    let receipt = try? JSONDecoder().decode(CompanionQuickReceipt.self, from: response)
                    continuation.resume(returning: receipt?.saved == true)
                }
            }
        }
        guard saved, store.ledger.timerControl?.token == token,
              store.ledger.timerControl?.onWatch == true,
              store.ledger.currentTimer?.id == before.currentTimer?.id,
              store.ledger.timerControl?.isFinished(at: Date()) == false else { throw ReproductionError.state }
        // A duplicate context and an older context must not undo the receipt.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                receiver.session(WCSession.default, didReceiveApplicationContext: ["timer": data])
                receiver.session(WCSession.default, didReceiveApplicationContext: ["timer": older])
                Task { @MainActor in continuation.resume() }
            }
        }
        guard store.ledger.timerControl?.token == token else { throw ReproductionError.state }
        if let activityBefore {
            guard let activity = Activity<TimerLiveAttributes>.activities.first,
                  activity.id == activityBefore.id, activity.content.state.token == token else { throw ReproductionError.activity }
        }
        withExtendedLifetime(receiver) {}
    }
    private enum ReproductionError: Error { case disabled, payload, state, activity }
}
#endif
