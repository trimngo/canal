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

    static func enqueue(_ entry: QuickCaptureEntry) throws {
        var item = try query()
        item[kSecAttrAccount as String] = entry.id
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecValueData as String] = try JSONEncoder().encode(entry)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw QueueError.keychain(status) }
    }

    static func pending() throws -> [QuickCaptureEntry] {
        var request = try query()
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [Data] else { throw QueueError.keychain(status) }
        return try items.map { try QuickCaptureEntry.decodeQueued($0) }
    }

    static func remove(_ entry: QuickCaptureEntry) throws {
        var item = try query(); item[kSecAttrAccount as String] = entry.id
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw QueueError.keychain(status) }
    }

    enum QueueError: LocalizedError {
        case unavailable, keychain(OSStatus)
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Siri capture storage is not available in this installation."
            case .keychain: return "The entry could not be saved securely. Unlock your Watch and try again."
            }
        }
    }
}
