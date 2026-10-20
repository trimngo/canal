import SwiftUI
import UIKit
import LedgerCore

extension UIApplication {
    func dismissLedgerKeyboard() {
        connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .filter(\.isKeyWindow).forEach { $0.endEditing(true) }
    }
}

// The recognizer observes taps without consuming the control's original tap.
// Text inputs keep focus when tapped, and drafts are never cleared on dismissal.
private final class OutsideInputTap: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    func configure() {
        addTarget(self, action: #selector(dismissInput))
        cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false
        delegate = self
    }
    @objc private func dismissInput() { view?.endEditing(true) }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var current: UIResponder? = touch.view
        while let candidate = current {
            // Alerts manage their own keyboard and actions. Ending editing
            // during Create moves the alert before its button receives the
            // completed tap, so the first tap only hides the keyboard.
            if candidate is UITextField || candidate is UITextView || candidate is UIControl || candidate is UIAlertController { return false }
            current = candidate.next
        }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

private struct KeyboardTapInstaller: UIViewRepresentable {
    final class Host: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0 is OutsideInputTap }) else { return }
            let tap = OutsideInputTap(target: nil, action: nil)
            tap.configure(); window.addGestureRecognizer(tap)
        }
    }
    func makeUIView(context: Context) -> Host { Host() }
    func updateUIView(_ view: Host, context: Context) {}
}

private struct InputDismissal: ViewModifier {
    func body(content: Content) -> some View {
        content.background(KeyboardTapInstaller().allowsHitTesting(false))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.dismissLedgerKeyboard() }
                        .accessibilityIdentifier("keyboard.done")
                }
            }
    }
}
extension View {
    func ledgerInputDismissal() -> some View { modifier(InputDismissal()) }
}

struct LogDeletionUndoBar: View {
    @EnvironmentObject private var store: LedgerStore
    var body: some View {
        if store.canUndoLogDeletion {
            HStack {
                Label("Log deleted", systemImage: "trash")
                Spacer()
                Button("Undo") { store.undoLogDeletion() }.fontWeight(.semibold)
                    .accessibilityIdentifier("logs.undo-delete")
            }.font(.subheadline).padding(12).background(.regularMaterial)
                .accessibilityElement(children: .contain)
        }
    }
}

struct DeleteLogButton: View {
    @EnvironmentObject private var store: LedgerStore
    let entry: CheckIn
    var identifierPrefix = "logs.delete"
    var body: some View {
        Button(role: .destructive) {
            do { try store.deleteLog(entry) } catch { store.report(error) }
        } label: {
            Label("Delete log", systemImage: "trash")
                .labelStyle(.iconOnly).frame(width: 44, height: 44)
        }.buttonStyle(.borderless)
            .disabled(!store.storageAvailable)
            .accessibilityLabel("Delete log: \(entry.activity)")
            .accessibilityHint("Undo is available for 15 seconds.")
            .accessibilityIdentifier("\(identifierPrefix).\(entry.id)")
    }
}
