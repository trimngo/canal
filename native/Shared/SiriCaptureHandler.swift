import Foundation
import Intents
import LedgerCore

/// Siri's built-in note grammar can carry free text in the same utterance.
/// App Shortcut trigger phrases cannot interpolate a free-form String.
final class SiriCaptureHandler: NSObject, INCreateNoteIntentHandling {
    static func text(from intent: INCreateNoteIntent) throws -> String {
        try QuickCapture.text(title: intent.title?.spokenPhrase,
                              body: (intent.content as? INTextNoteContent)?.text)
    }

    func resolveTitle(for intent: INCreateNoteIntent, with completion: @escaping (INSpeakableStringResolutionResult) -> Void) {
        if let title = intent.title, !title.spokenPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completion(.success(with: title))
        } else if let body = (intent.content as? INTextNoteContent)?.text,
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completion(.notRequired())
        } else { completion(.needsValue()) }
    }

    func resolveContent(for intent: INCreateNoteIntent, with completion: @escaping (INNoteContentResolutionResult) -> Void) {
        if let content = intent.content as? INTextNoteContent,
           !content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completion(.success(with: content))
        } else if (try? Self.text(from: intent)) != nil { completion(.notRequired()) }
        else { completion(.needsValue()) }
    }

    func resolveGroupName(for intent: INCreateNoteIntent, with completion: @escaping (INSpeakableStringResolutionResult) -> Void) {
        // All new thoughts belong in the Inbox; don't ask which folder.
        completion(.notRequired())
    }

    func confirm(intent: INCreateNoteIntent, completion: @escaping (INCreateNoteIntentResponse) -> Void) {
        completion(INCreateNoteIntentResponse(code: (try? Self.text(from: intent)) == nil ? .failure : .ready,
                                               userActivity: nil))
    }

    func handle(intent: INCreateNoteIntent, completion: @escaping (INCreateNoteIntentResponse) -> Void) {
        let receivedAt = Date()
        let text = Result { try Self.text(from: intent) }
        Task { @MainActor in
            do {
                let store = LedgerStore.shared; store.start()
                let capture = try store.addCapture(text.get(), at: receivedAt)
                let response = INCreateNoteIntentResponse(code: .success, userActivity: nil)
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: capture.createdAt)
                response.createdNote = INNote(title: INSpeakableString(spokenPhrase: capture.text),
                    contents: [INTextNoteContent(text: capture.text)], groupName: INSpeakableString(spokenPhrase: "Inbox"),
                    createdDateComponents: components, modifiedDateComponents: components, identifier: capture.id)
                completion(response)
            } catch {
                completion(INCreateNoteIntentResponse(code: .failure, userActivity: nil))
            }
        }
    }
}
