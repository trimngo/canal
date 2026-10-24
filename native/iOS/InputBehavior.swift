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
    let keyboardPreservingRegions = NSHashTable<UIView>.weakObjects()
    private weak var inputToDismiss: UIView?
    func configure() {
        addTarget(self, action: #selector(dismissInput))
        cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false
        delegate = self
    }
    @objc private func dismissInput() {
        // Let the tapped SwiftUI control finish its action before keyboard
        // dismissal moves the control underneath the completed touch.
        let input = inputToDismiss
        DispatchQueue.main.async { [weak input] in input?.resignFirstResponder() }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        for region in keyboardPreservingRegions.allObjects where region.window === touch.view?.window && !region.isHidden {
            if region.bounds.contains(touch.location(in: region)) { return false }
        }
        var current: UIResponder? = touch.view
        while let candidate = current {
            // Alerts manage their own keyboard and actions. Ending editing
            // during Create moves the alert before its button receives the
            // completed tap, so the first tap only hides the keyboard.
            if candidate is UITextField || candidate is UITextView || candidate is UIControl || candidate is UIAlertController { return false }
            current = candidate.next
        }
        inputToDismiss = view.flatMap { firstResponder(in: $0) }
        return inputToDismiss != nil
    }
    private func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for child in view.subviews { if let input = firstResponder(in: child) { return input } }
        return nil
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

private struct KeyboardTapInstaller: UIViewRepresentable {
    var preservesKeyboard = false
    final class Host: UIView {
        var preservesKeyboard = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            let tap: OutsideInputTap
            if let existing = window.gestureRecognizers?.first(where: { $0 is OutsideInputTap }) as? OutsideInputTap { tap = existing }
            else { tap = OutsideInputTap(target: nil, action: nil); tap.configure(); window.addGestureRecognizer(tap) }
            if preservesKeyboard { tap.keyboardPreservingRegions.add(self) }
        }
    }
    func makeUIView(context: Context) -> Host { let host = Host(); host.preservesKeyboard = preservesKeyboard; return host }
    func updateUIView(_ view: Host, context: Context) {}
}

private struct InputDismissal: ViewModifier {
    var preservingKeyboard: Bool
    var showsKeyboardDone: Bool
    func body(content: Content) -> some View {
        content.background(KeyboardTapInstaller(preservesKeyboard: preservingKeyboard).allowsHitTesting(false))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if showsKeyboardDone {
                        Spacer()
                        Button("Done") { UIApplication.shared.dismissLedgerKeyboard() }
                            .accessibilityIdentifier("keyboard.done")
                    }
                }
            }
    }
}
extension View {
    func ledgerPreserveKeyboard() -> some View {
        background(KeyboardTapInstaller(preservesKeyboard: true).allowsHitTesting(false))
    }
    func ledgerInputDismissal(preservingKeyboard: Bool = false, showsKeyboardDone: Bool = true) -> some View {
        modifier(InputDismissal(preservingKeyboard: preservingKeyboard, showsKeyboardDone: showsKeyboardDone))
    }
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
