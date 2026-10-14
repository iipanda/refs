import Foundation

/// Bounds synchronous work that may remain blocked after its caller stops waiting.
///
/// Calls for the same key share the first call's deadline. Once that deadline expires, or all
/// callers cancel, further calls for the key return nil until the underlying operation exits.
/// Different keys return nil immediately when all worker slots are occupied; work is never queued
/// behind a blocked operation. A timeout releases callers, but cannot interrupt synchronous work.
public final class BoundedBlockingLookup<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    // Waiters cross queue boundaries but their mutable fields remain confined to stateQueue.
    private final class Waiter: @unchecked Sendable {
        let id = UUID()
        var continuation: CheckedContinuation<Value?, Never>?
        var key: Key?
        var cancelled = false
    }

    private final class Operation {
        let id = UUID()
        let deadline: DispatchTime
        var waiters: [UUID: Waiter] = [:]
        var expired = false
        var timer: DispatchSourceTimer?

        init(deadline: DispatchTime) {
            self.deadline = deadline
        }

        func stopTimer() {
            timer?.cancel()
            timer = nil
        }
    }

    private let maxConcurrentOperations: Int
    private let stateQueue = DispatchQueue(label: "refs.blocking-lookup.state")
    private let workerQueue = DispatchQueue(label: "refs.blocking-lookup.workers", qos: .userInitiated,
                                            attributes: .concurrent)
    // Only stateQueue reads or writes operations and waiter state.
    private var operations: [Key: Operation] = [:]

    public init(maxConcurrentOperations: Int = 2) {
        precondition(maxConcurrentOperations > 0)
        self.maxConcurrentOperations = maxConcurrentOperations
    }

    public func value(for key: Key, timeout: TimeInterval,
                      operation: @escaping @Sendable () -> Value) async -> Value? {
        guard timeout.isFinite, timeout > 0, !Task.isCancelled else { return nil }
        let waiter = Waiter()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                stateQueue.async {
                    self.register(waiter, continuation: continuation, key: key,
                                  timeout: timeout, operation: operation)
                }
            }
        } onCancel: {
            // Enqueuing cancellation also handles cancellation before registration. The waiter
            // retains that flag until register installs its continuation and immediately resumes it.
            stateQueue.async { self.cancel(waiter) }
        }
    }

    private func register(_ waiter: Waiter, continuation: CheckedContinuation<Value?, Never>,
                          key: Key, timeout: TimeInterval,
                          operation: @escaping @Sendable () -> Value) {
        waiter.continuation = continuation
        guard !waiter.cancelled else { resume(waiter, with: nil); return }

        if let existing = operations[key] {
            if DispatchTime.now() >= existing.deadline { expire(key: key, id: existing.id) }
            guard !existing.expired else { resume(waiter, with: nil); return }
            waiter.key = key
            existing.waiters[waiter.id] = waiter
            return
        }

        guard operations.count < maxConcurrentOperations else { resume(waiter, with: nil); return }
        let pending = Operation(deadline: .now() + timeout)
        let operationID = pending.id
        waiter.key = key
        pending.waiters[waiter.id] = waiter
        operations[key] = pending

        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: pending.deadline)
        timer.setEventHandler { [weak self] in self?.expire(key: key, id: operationID) }
        pending.timer = timer
        timer.resume()

        // Blocking APIs never run on Swift's cooperative executor or on the state/timer queue.
        workerQueue.async {
            let result = operation()
            self.stateQueue.async { self.finish(key: key, id: operationID, result: result) }
        }
    }

    private func expire(key: Key, id: UUID) {
        guard let pending = operations[key], pending.id == id else { return }
        pending.expired = true
        pending.stopTimer()
        let waiters = Array(pending.waiters.values)
        pending.waiters.removeAll()
        for waiter in waiters { resume(waiter, with: nil) }
        // Keep the entry and worker slot until finish runs, even if the operation never returns.
    }

    private func cancel(_ waiter: Waiter) {
        waiter.cancelled = true
        if let key = waiter.key, let pending = operations[key] {
            pending.waiters.removeValue(forKey: waiter.id)
            if pending.waiters.isEmpty {
                pending.expired = true
                pending.stopTimer()
            }
        }
        resume(waiter, with: nil)
    }

    private func finish(key: Key, id: UUID, result: Value) {
        guard let pending = operations[key], pending.id == id else { return }
        // Deadline checks also protect callers if the timer delivery is delayed by scheduling.
        if DispatchTime.now() >= pending.deadline { expire(key: key, id: id) }
        operations.removeValue(forKey: key)
        pending.stopTimer()
        for waiter in pending.waiters.values { resume(waiter, with: result) }
    }

    private func resume(_ waiter: Waiter, with result: Value?) {
        let continuation = waiter.continuation
        waiter.continuation = nil
        waiter.key = nil
        continuation?.resume(returning: result)
    }
}
