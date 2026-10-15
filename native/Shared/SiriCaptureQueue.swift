import Foundation
import Security
import LedgerCore

/// The Watch app and its Siri extension share only this narrow, durable inbox.
/// Each thought is a separate Keychain item, so concurrent app/extension writes
/// cannot replace the ledger or one another. Existing ledger files stay put.
enum SiriCaptureQueue {
    private static let service = "com.trimngo.TimeLedger.siri-captures"

    private static func query() throws -> [String: Any] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "LedgerCaptureAccessGroup") as? String,
              !group.isEmpty, !group.contains("$(") else { throw QueueError.unavailable }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccessGroup as String: group]
    }

    static func enqueue(_ text: String, at date: Date) throws -> Capture {
        var ledger = Ledger()
        let capture = try ledger.addCapture(text: text, writer: "watch-siri", now: date)
        var item = try query()
        item[kSecAttrAccount as String] = capture.id
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecValueData as String] = try JSONEncoder().encode(capture)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw QueueError.keychain(status) }
        return capture
    }

    static func pending() throws -> [Capture] {
        var request = try query()
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [Data] else { throw QueueError.keychain(status) }
        return try items.map { try JSONDecoder().decode(Capture.self, from: $0) }
    }

    static func remove(_ capture: Capture) throws {
        var item = try query(); item[kSecAttrAccount as String] = capture.id
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw QueueError.keychain(status) }
    }

    enum QueueError: LocalizedError {
        case unavailable, keychain(OSStatus)
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Siri capture storage is not available in this installation."
            case .keychain: return "The thought could not be saved securely. Unlock your Watch and try again."
            }
        }
    }
}
