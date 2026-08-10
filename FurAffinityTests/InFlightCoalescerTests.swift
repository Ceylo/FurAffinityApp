//
//  InFlightCoalescerTests.swift
//  FurAffinityTests
//
//  Coverage for the same-key coalescing that keeps a shared image from being
//  stored twice into the Kingfisher disk cache.
//

import Foundation
import Testing
@testable import Fur_Affinity

private actor Counter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private struct TestError: Error {}

/// Blocks its waiters until opened.
private actor Gate {
    private var isOpen = false
    private var continuations = [CheckedContinuation<Void, Never>]()

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

/// Waits for `expected` callers to have reached their `coalescer.run` call, then opens
/// `gate` so the single in-flight operation can finish. Joiners suspend inside the
/// coalescer rather than in the operation, so they can't be counted by the gate itself
/// — the small settle delay covers the hop between incrementing `arrivals` and
/// entering the actor.
private func releaseWhenAllArrived(_ gate: Gate, arrivals: Counter, expected: Int) async {
    while await arrivals.count < expected {
        await Task.yield()
    }
    try? await Task.sleep(for: .milliseconds(50))
    await gate.open()
}

struct InFlightCoalescerTests {
    /// Callers arriving while an operation for the same key is in flight must join it
    /// instead of running their own — that is what collapses the duplicate cache store.
    @Test
    func concurrentCallsForSameKeyRunOperationOnce() async throws {
        let coalescer = InFlightCoalescer<String>()
        let runs = Counter()
        let arrivals = Counter()
        let gate = Gate()

        let successes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 16 {
                group.addTask {
                    await arrivals.increment()
                    do {
                        try await coalescer.run("key") {
                            await runs.increment()
                            // Hold the operation open so every caller joins it.
                            await gate.wait()
                        }
                        return true
                    } catch {
                        return false
                    }
                }
            }

            await releaseWhenAllArrived(gate, arrivals: arrivals, expected: 16)

            var collected = [Bool]()
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Every caller observed completion, but the work happened once.
        #expect(successes.count == 16)
        #expect(successes.allSatisfy { $0 })
        #expect(await runs.count == 1)
    }

    @Test
    func distinctKeysEachRunTheirOwnOperation() async throws {
        let coalescer = InFlightCoalescer<String>()
        let runs = Counter()

        async let first: Void = coalescer.run("a") { await runs.increment() }
        async let second: Void = coalescer.run("b") { await runs.increment() }
        _ = try await (first, second)

        #expect(await runs.count == 2)
    }

    /// A failure must reach every waiter, and the key must be cleared so the next
    /// caller retries rather than replaying the stale failure forever.
    @Test
    func thrownErrorReachesAllWaitersAndKeyIsCleared() async throws {
        let coalescer = InFlightCoalescer<String>()
        let runs = Counter()
        let arrivals = Counter()
        let gate = Gate()

        let failures = await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    await arrivals.increment()
                    do {
                        try await coalescer.run("key") {
                            await runs.increment()
                            await gate.wait()
                            throw TestError()
                        }
                        return false
                    } catch {
                        return error is TestError
                    }
                }
            }

            await releaseWhenAllArrived(gate, arrivals: arrivals, expected: 8)

            var collected = [Bool]()
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        #expect(failures.count == 8)
        #expect(failures.allSatisfy { $0 })
        #expect(await runs.count == 1)

        // Key cleared: a later call runs the operation again.
        try await coalescer.run("key") { await runs.increment() }
        #expect(await runs.count == 2)
    }
}
