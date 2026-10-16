import Foundation
import Intents
import LedgerCore

/// Siri's built-in note grammar can carry free text in the same utterance.
/// App Shortcut trigger phrases cannot interpolate a free-form String.
final class SiriCaptureHandler: NSObject, INCreateNoteIntentHandling {
    static func text(from intent: INCreateNoteIntent) throws -> String {
        try QuickCapture.note(title: intent.title?.spokenPhrase,
                              body: (intent.content as? INTextNoteContent)?.text).text
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
        if let content = intent.content as? INTextNoteContent, let text = content.text,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        let entry = Result { try QuickCapture.note(title: intent.title?.spokenPhrase,
            body: (intent.content as? INTextNoteContent)?.text, at: receivedAt) }
        Task { @MainActor in
            do {
                let saved = try entry.get()
                #if LEDGER_INTENTS_EXTENSION
                try SiriCaptureQueue.enqueue(saved)
                #else
                let store = LedgerStore.shared; store.start()
                try store.saveSiriEntry(saved)
                #endif
                let response = INCreateNoteIntentResponse(code: .success, userActivity: nil)
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: saved.recordedAt)
                response.createdNote = INNote(title: INSpeakableString(spokenPhrase: saved.text),
                    contents: [INTextNoteContent(text: saved.text)],
                    groupName: INSpeakableString(spokenPhrase: saved.destination == .idea ? "Inbox" : "Activity log"),
                    createdDateComponents: components, modifiedDateComponents: components, identifier: saved.id)
                completion(response)
            } catch {
                completion(INCreateNoteIntentResponse(code: .failure, userActivity: nil))
            }
        }
    }
}
