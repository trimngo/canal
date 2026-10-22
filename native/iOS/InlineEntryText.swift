import SwiftUI

/// Shared inline editing for saved idea/log text. Only finishing an edit writes
/// data; typing never records a ranking answer or changes labels/timestamps.
struct InlineEntryText: View {
    @Environment(\.scenePhase) private var scenePhase
    let text: String
    let identifier: String
    var font: Font = .body
    var maxLength: Int? = nil
    let save: (String) throws -> Void
    @State private var draft: String
    @State private var error: String?
    @State private var editing = false
    @FocusState private var focused: Bool

    init(text: String, identifier: String, font: Font = .body, maxLength: Int? = nil, save: @escaping (String) throws -> Void) {
        self.text = text; self.identifier = identifier; self.font = font; self.maxLength = maxLength; self.save = save
        _draft = State(initialValue: text)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if editing {
                TextField("Entry text", text: $draft, axis: .vertical)
                    .font(font).lineLimit(1...12).focused($focused).submitLabel(.done)
                    .accessibilityIdentifier(identifier).accessibilityLabel("Edit entry text")
                    .onSubmit { if finish() { focused = false; editing = false } }
                    .task { focused = true }
            } else {
                Text(text).font(font).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .onTapGesture { draft = text; editing = true }
                    .accessibilityIdentifier(identifier).accessibilityHint("Tap to edit inline")
                    .accessibilityAction(named: "Edit text") { draft = text; editing = true }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("\(identifier).error") }
        }.onChange(of: focused) { old, value in if old && !value, finish() { editing = false } }
            .onChange(of: text) { _, value in if !editing { draft = value } }
            .onChange(of: scenePhase) { _, value in if value != .active { finish() } }
            .onDisappear { finish() }
    }
    @discardableResult private func finish() -> Bool {
        guard editing, draft != text else { return true }
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { error = "Enter some text."; return false }
        if let maxLength, value.count > maxLength { error = "Keep this entry to \(maxLength) characters."; return false }
        do { try save(value); draft = value; error = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
}
