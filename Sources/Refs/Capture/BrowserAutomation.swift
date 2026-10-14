import Foundation
import RefsCore

/// Bridges potentially unbounded Apple Event calls without occupying Swift's cooperative workers.
/// Native calls cannot be cancelled; the lookup keeps their slots until they actually return.
final class BrowserAutomation: @unchecked Sendable {
    private struct PermissionKey: Hashable, Sendable {
        var bundleID: String
        var ask: Bool
    }

    private let permissions: BoundedBlockingLookup<PermissionKey, BrowserSupport.Permission>
    // NSAppleScript execution must stay serialized, independently of stuck permission queries.
    private let tabRequests = BoundedBlockingLookup<String, [BrowserTab]>(maxConcurrentOperations: 1)
    private let permissionLookup: @Sendable (String, Bool) -> BrowserSupport.Permission
    private let tabLookup: @Sendable (BrowserSupport.Browser) -> [BrowserTab]

    init(
        maxConcurrentOperations: Int = 2,
        permissionLookup: @escaping @Sendable (String, Bool) -> BrowserSupport.Permission,
        tabLookup: @escaping @Sendable (BrowserSupport.Browser) -> [BrowserTab]
    ) {
        permissions = BoundedBlockingLookup(maxConcurrentOperations: maxConcurrentOperations)
        self.permissionLookup = permissionLookup
        self.tabLookup = tabLookup
    }

    func permission(for bundleID: String, ask: Bool, timeout: TimeInterval? = nil) async -> BrowserSupport.Permission {
        let result = await availableValue(in: permissions, for: PermissionKey(bundleID: bundleID, ask: ask),
                                          timeout: timeout ?? (ask ? 120 : 0.6)) {
            self.permissionLookup(bundleID, ask)
        }
        return result ?? .unknown(-1712) // errAETimeout
    }

    func tabs(for browser: BrowserSupport.Browser, timeout: TimeInterval = 1.2) async -> [BrowserTab] {
        let result = await availableValue(in: tabRequests, for: browser.bundleID, timeout: timeout) {
            self.tabLookup(browser)
        }
        return result ?? []
    }

    /// A busy slot is normal when several browsers are prefetched. Retry asynchronously within
    /// the caller's original budget; never queue more native work or extend the deadline.
    private func availableValue<Key: Hashable & Sendable, Value: Sendable>(
        in lookup: BoundedBlockingLookup<Key, Value>, for key: Key, timeout: TimeInterval,
        operation: @escaping @Sendable () -> Value
    ) async -> Value? {
        guard timeout.isFinite, timeout > 0 else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !Task.isCancelled {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            if let value = await lookup.value(for: key, timeout: remaining, operation: operation) { return value }
            // The native call may have timed out, or a different key may be holding the slot.
            // BoundedBlockingLookup retains blocked slots and rejects retries without spawning.
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch { return nil }
        }
        return nil
    }
}
