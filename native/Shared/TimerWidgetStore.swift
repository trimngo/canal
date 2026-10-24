#if os(watchOS)
import Foundation
import Security
import LedgerCore

/// Only the current timer summary is shared with the complication, not logs.
enum TimerWidgetStore {
    private static func query() throws -> [String: Any] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "LedgerCaptureAccessGroup") as? String,
              !group.isEmpty, !group.contains("$(") else { throw CocoaError(.fileReadNoPermission) }
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.trimngo.TimeLedger.timer-widget",
                kSecAttrAccount as String: "current", kSecAttrAccessGroup as String: group]
    }
    static func read() -> TimerWidgetSnapshot? {
        guard var request = try? query() else { return nil }
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(TimerWidgetSnapshot.self, from: data)
    }
    static func write(_ value: TimerWidgetSnapshot?) throws -> Bool {
        guard read() != value else { return false }
        var request = try query()
        guard let value else { SecItemDelete(request as CFDictionary); return true }
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
        } else if status != errSecSuccess { throw CocoaError(.fileWriteUnknown) }
        return true
    }
}
#endif
