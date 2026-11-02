import Foundation

/// Thread-safe callback evidence for Observation's Sendable invalidation closure.
final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    func mark() { lock.lock(); defer { lock.unlock() }; changed = true }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return changed }
}
