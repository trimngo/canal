import Foundation

public enum AllocationPlanError: LocalizedError {
    case incomplete, staleUndo
    public var errorDescription: String? {
        switch self {
        case .incomplete: return "Assign exactly 100% across your life areas. Other percentages stay unchanged."
        case .staleUndo: return "Categories or goals have changed, or the new parent is already in use. This move can no longer be undone safely."
        }
    }
}

/// Text stays intact while a plan is incomplete. Unedited values retain their
/// original precision, even when the field displays fewer decimal places.
public struct AllocationPlanDraft: Equatable, Sendable {
    public var text: [String: String]
    private var originalText: [String: String]
    private var originalValues: [String: Double]
    public init(_ values: [String: Double], maximumFractionDigits: Int = 8) {
        originalValues = values
        text = values.mapValues { $0.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...maximumFractionDigits))) }
        originalText = text
    }
    public var isDirty: Bool { text.filter { !$0.value.isEmpty } != originalText }
    public var values: [String: Double]? {
        var result: [String: Double] = [:]
        for (id, entry) in text {
            let value = entry.trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }
            if entry == originalText[id], let original = originalValues[id] { result[id] = original; continue }
            guard value.range(of: "^(?:[0-9]+(?:[.,][0-9]*)?|[.,][0-9]+)$", options: .regularExpression) != nil,
                  let number = Double(value.replacingOccurrences(of: ",", with: ".")), number.isFinite,
                  (0...100).contains(number) else { return nil }
            result[id] = number
        }
        return result
    }
    public var total: Double? { values.map { $0.values.reduce(0, +) } }
    public var isComplete: Bool { values.map { (try? Ledger.validateAllocationPlan($0)) != nil } ?? false }
    public mutating func useRemaining(for id: String) {
        var others = self
        others.text.removeValue(forKey: id)
        guard let total = others.total, total <= 100 else { return }
        text[id] = (100 - total).formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...8)))
    }
}

extension Ledger {
    public static func validateAllocationPlan(_ values: [String: Double]) throws {
        try validateTargets(values)
        guard abs(values.values.reduce(0, +) - 100) < 0.0000001 else { throw AllocationPlanError.incomplete }
    }
    public mutating func saveAllocationPlan(_ values: [String: Double], effectiveAt: Date = Date(), writer: String) throws {
        try Self.validateAllocationPlan(values)
        try saveTargets(values, effectiveAt: effectiveAt, writer: writer)
    }
}
