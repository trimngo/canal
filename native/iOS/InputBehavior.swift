import SwiftUI
import UIKit

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
        var current = touch.view
        while let candidate = current {
            if candidate is UITextField || candidate is UITextView { return false }
            current = candidate.superview
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
