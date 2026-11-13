//
//  FAImageStoreTests.swift
//  FurAffinityUITests (Android)
//

import Foundation
import Testing
@testable import FurAffinityUI

private final class Saturated: @unchecked Sendable {
    let store = FAImageStore()
    private let lock = NSLock()
    private var running = 0
    private var admitted = [String]()
    private let blockers = DispatchSemaphore(value: 0)
    private var tasks = [Task<Void, Never>]()

    init() async throws {
        for _ in 0..<6 {
            tasks.append(Task { [store, self] in
                await store.decoding(.low, for: URL(string: "https://example.com/blocker")!) {
                    self.lock.withLock { self.running += 1 }
                    self.blockers.wait()
                }
            })
        }
        try await until { self.lock.withLock { self.running } == 6 }
    }

    func enqueue(_ name: String, _ priority: FAImagePriority) async throws {
        let before = await store.queuedCount
        tasks.append(Task { [store, self] in
            await store.decoding(priority, for: Self.url(name)) {
                self.lock.withLock { self.admitted.append(name) }
            }
        })
        try await until { await self.store.queuedCount == before + 1 }
    }

    func admissionOrder() async throws -> [String] {
        let queued = await store.queuedCount
        blockers.signal()
        try await until { self.lock.withLock { self.admitted.count } == queued }
        return lock.withLock { admitted }
    }

    func finish() async {
        for _ in 0..<6 { blockers.signal() }
        for task in tasks { await task.value }
    }

    static func url(_ name: String) -> URL {
        URL(string: "https://example.com/\(name)")!
    }

    private func until(_ condition: @escaping () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while await !condition() {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@Suite(.serialized) struct FAImageStoreTests {
    @Test func promoteMovesQueuedWaitersAhead() async throws {
        let gate = try await Saturated()
        try await gate.enqueue("a", .low)
        try await gate.enqueue("b", .low)
        try await gate.enqueue("c", .low)
        await gate.store.promote(Saturated.url("c"))
        #expect(try await gate.admissionOrder() == ["c", "a", "b"])
        await gate.finish()
    }

    @Test func promotionOutlivesOneOfTwoVisibleLoads() async throws {
        let gate = try await Saturated()
        let url = Saturated.url("shared")
        await gate.store.promote(url)
        await gate.store.promote(url)
        await gate.store.forgetPromotion(url)
        try await gate.enqueue("a", .low)
        try await gate.enqueue("shared", .low)
        #expect(try await gate.admissionOrder() == ["shared", "a"])
        await gate.finish()
    }

    @Test func forgottenPromotionQueuesLow() async throws {
        let gate = try await Saturated()
        let url = Saturated.url("shared")
        await gate.store.promote(url)
        await gate.store.forgetPromotion(url)
        try await gate.enqueue("a", .low)
        try await gate.enqueue("shared", .low)
        #expect(try await gate.admissionOrder() == ["a", "shared"])
        await gate.finish()
    }
}
