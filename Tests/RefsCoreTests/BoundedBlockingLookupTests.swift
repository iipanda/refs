import Foundation
import Testing
@testable import RefsCore

@Suite struct BoundedBlockingLookupTests {
    @Test func stalledOperationTimesOutWithoutReleasingItsWorkerSlot() async {
        let lookup = BoundedBlockingLookup<String, Int>(maxConcurrentOperations: 1)
        let work = BlockingWork()
        defer { work.release() }

        let started = Date()
        let result = await lookup.value(for: "browser", timeout: 0.08) { work.run() }
        #expect(result == nil)
        #expect(Date().timeIntervalSince(started) < 1)
        #expect(work.invocations == 1)

        let retryStarted = Date()
        let retry = await lookup.value(for: "browser", timeout: 5) { work.run() }
        #expect(retry == nil)
        #expect(Date().timeIntervalSince(retryStarted) < 0.5)
        #expect(work.invocations == 1)
    }

    @Test func twentyCallsForTheSameKeyStartOnlyOneOperation() async {
        let lookup = BoundedBlockingLookup<String, Int>()
        let work = BlockingWork()
        defer { work.release() }

        let results = await withTaskGroup(of: Int?.self, returning: [Int?].self) { group in
            for _ in 0..<20 {
                group.addTask { await lookup.value(for: "browser", timeout: 0.1) { work.run() } }
            }
            var results: [Int?] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(results.count == 20)
        #expect(results.allSatisfy { $0 == nil })
        #expect(work.invocations == 1)
    }

    @Test func saturationRejectsAdditionalWorkIncludingAfterTimeout() async {
        let lookup = BoundedBlockingLookup<String, Int>(maxConcurrentOperations: 2)
        let work = BlockingWork()
        defer { work.release(count: 2) }
        let first = Task { await lookup.value(for: "one", timeout: 0.2) { work.run() } }
        let second = Task { await lookup.value(for: "two", timeout: 0.2) { work.run() } }
        #expect(await waitUntil { work.invocations == 2 })

        let rejected = await lookup.value(for: "three", timeout: 5) { work.run() }
        #expect(rejected == nil)
        #expect(await first.value == nil)
        #expect(await second.value == nil)
        let rejectedAfterTimeout = await lookup.value(for: "four", timeout: 5) { work.run() }
        #expect(rejectedAfterTimeout == nil)
        #expect(work.invocations == 2)
        #expect(work.maximumActive == 2)
    }

    @Test func cancellationReturnsPromptlyAndKeepsTheBlockedOperationBounded() async {
        let lookup = BoundedBlockingLookup<String, Int>(maxConcurrentOperations: 1)
        let work = BlockingWork()
        defer { work.release() }
        let caller = Task { await lookup.value(for: "browser", timeout: 5) { work.run() } }
        #expect(await waitUntil { work.invocations == 1 })

        let cancelled = Date()
        caller.cancel()
        #expect(await caller.value == nil)
        #expect(Date().timeIntervalSince(cancelled) < 0.5)
        #expect(await lookup.value(for: "browser", timeout: 5) { work.run() } == nil)
        #expect(await lookup.value(for: "other", timeout: 5) { work.run() } == nil)
        #expect(work.invocations == 1)
    }

    @Test func cancellingOneCoalescedCallerDoesNotCancelTheOthers() async {
        let lookup = BoundedBlockingLookup<String, Int>()
        let work = BlockingWork()
        defer { work.release() }
        let first = Task { await lookup.value(for: "browser", timeout: 1) { work.run() } }
        #expect(await waitUntil { work.invocations == 1 })
        let second = Task { await lookup.value(for: "browser", timeout: 1) { work.run() } }
        // Give the calls time to overlap. Cancelling the newer caller preserves the first caller
        // even if a heavily loaded executor has not scheduled the second one yet.
        try? await Task.sleep(for: .milliseconds(20))
        second.cancel()
        #expect(await second.value == nil)
        work.release()
        #expect(await first.value == 42)
        #expect(work.invocations == 1)
    }

    @Test func lateResultIsDiscardedAndActualCompletionAllowsAnotherLookup() async {
        let lookup = BoundedBlockingLookup<String, Int>(maxConcurrentOperations: 1)
        let work = BlockingWork()
        defer { work.release() }
        let first = await lookup.value(for: "browser", timeout: 0.08) { work.run() }
        #expect(first == nil)
        work.release()
        #expect(await waitUntil { work.active == 0 })

        // Returning from run and processing finish happen on separate queues. Retry only until the
        // bounded worker slot becomes available; the first late value must never be returned.
        var result: Int?
        for _ in 0..<100 {
            result = await lookup.value(for: "browser", timeout: 1) { 99 }
            if result != nil { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(result == 99)
        #expect(first == nil)
        #expect(await lookup.value(for: "other", timeout: 1) { 7 } == 7)
    }

    @Test func anAlreadyCancelledCallerDoesNotStartWork() async {
        let lookup = BoundedBlockingLookup<String, Int>()
        let work = BlockingWork()
        defer { work.release() }
        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await lookup.value(for: "browser", timeout: 1) { work.run() }
        }
        #expect(await caller.value == nil)
        #expect(work.invocations == 0)
    }

    private func waitUntil(_ predicate: @escaping @Sendable () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return predicate()
    }
}

private final class BlockingWork: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var invocationCount = 0
    private var activeCount = 0
    private var maximumActiveCount = 0

    var invocations: Int { lock.withLock { invocationCount } }
    var active: Int { lock.withLock { activeCount } }
    var maximumActive: Int { lock.withLock { maximumActiveCount } }

    func run() -> Int {
        lock.withLock {
            invocationCount += 1
            activeCount += 1
            maximumActiveCount = max(maximumActiveCount, activeCount)
        }
        // Finite blocking plus each test's deferred release keeps failures from stranding threads.
        _ = gate.wait(timeout: .now() + 5)
        lock.withLock { activeCount -= 1 }
        return 42
    }

    func release(count: Int = 1) {
        for _ in 0..<count { gate.signal() }
    }
}
