import SwiftUI
import LedgerCore

/// The same single-item actions in ranking and independent categorization.
struct CaptureReviewActions: View {
    @EnvironmentObject private var store: LedgerStore
    let capture: Capture
    let identifier: String
    var beforeChange: (() throws -> Void)? = nil
    var onDetails: (() -> Void)? = nil
    var onHandled: () -> Void = {}
    var onSnooze: ((Capture) -> Void)? = nil
    var body: some View {
        HStack(spacing: 12) {
            Button(capture.isDone ? "Reopen" : "Mark done", systemImage: capture.isDone ? "arrow.uturn.backward" : "checkmark.circle") {
                do { try beforeChange?(); try store.setCaptureDone(capture, done: !capture.isDone); onHandled() } catch { store.report(error) }
            }.accessibilityIdentifier("\(identifier).done")
            Spacer(minLength: 0)
            if let onDetails {
                Button(action: onDetails) { Image(systemName: "text.bubble").frame(width: 44, height: 44) }
                    .accessibilityLabel("Details").accessibilityIdentifier("\(identifier).notes.expand")
            }
            Menu {
                if let onSnooze { Button("Snooze", systemImage: "moon.zzz") { do { try beforeChange?(); onSnooze(capture) } catch { store.report(error) } } }
                Button(capture.isReference == true ? "Move to New Ideas" : "Move to Reference") {
                    do { try beforeChange?(); try store.setCaptureReference(capture, reference: capture.isReference != true); onHandled() } catch { store.report(error) }
                }.accessibilityIdentifier("\(identifier).reference")
            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                .accessibilityLabel("More idea actions").accessibilityIdentifier("\(identifier).actions")
            Button(role: .destructive) {
                do { try store.deleteCapture(capture); onHandled() } catch { store.report(error) }
            } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel("Delete idea: \(capture.text)").accessibilityIdentifier("\(identifier).delete")
        }.font(.subheadline).buttonStyle(.borderless)
    }
}
