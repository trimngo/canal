import Intents

final class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any? {
        intent is INCreateNoteIntent ? SiriCaptureHandler() : nil
    }
}
