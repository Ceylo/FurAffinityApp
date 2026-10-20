//
//  StagedDeletionTests.swift
//  FurAffinityTests
//

import Foundation
import Testing
#if FA_SKIP_MODULE
@testable import FurAffinityUI
#else
@testable import Fur_Affinity
#endif

@MainActor
struct StagedDeletionTests {
    struct SendError: Error {}

    @MainActor
    final class Recorder {
        var sent = [[Int]]()
        var restored = [[Int]]()
        var failSend = false
        var gate: CheckedContinuation<Void, Never>?
        var holdSend = false
    }

    private func makeDeletion() -> (StagedDeletion<Int>, Recorder) {
        let recorder = Recorder()
        let deletion = StagedDeletion<Int>(
            label: "items",
            send: { items in
                recorder.sent.append(items)
                if recorder.holdSend {
                    await withCheckedContinuation { recorder.gate = $0 }
                }
                if recorder.failSend { throw SendError() }
            },
            restore: { recorder.restored.append($0) }
        )
        return (deletion, recorder)
    }

    @Test func stage_doesNotSend() async throws {
        let (deletion, recorder) = makeDeletion()

        deletion.stage([1, 2])
        try await Task.sleep(for: .milliseconds(100))

        #expect(deletion.staged == [1, 2])
        #expect(deletion.hides { $0 == 1 })
        #expect(recorder.sent.isEmpty)
    }

    @Test func undo_restoresWithoutSending() async throws {
        let (deletion, recorder) = makeDeletion()
        deletion.stage([1, 2])

        deletion.undo()
        await deletion.commitTimer?.value

        #expect(recorder.restored == [[1, 2]])
        #expect(deletion.staged.isEmpty)
        #expect(!deletion.hides { $0 == 1 })
        #expect(deletion.commit() == nil)
        #expect(recorder.sent.isEmpty)
    }

    @Test func stage_commitsAfterUndoDelay() async {
        let (deletion, recorder) = makeDeletion()
        deletion.undoDelay = .milliseconds(100)

        deletion.stage([1])
        await deletion.commitTimer?.value

        #expect(recorder.sent == [[1]])
        #expect(deletion.staged.isEmpty)
    }

    @Test func stage_commitsPreviousBatch() async throws {
        let (deletion, recorder) = makeDeletion()

        deletion.stage([1])
        deletion.stage([2])
        try await Task.sleep(for: .milliseconds(100))

        #expect(recorder.sent == [[1]])
        #expect(deletion.staged == [2])
    }

    @Test func commit_restoresOnFailure() async {
        let (deletion, recorder) = makeDeletion()
        recorder.failSend = true
        deletion.stage([1])

        await deletion.commit()?.value

        #expect(recorder.sent == [[1]])
        #expect(recorder.restored == [[1]])
        #expect(!deletion.hides { $0 == 1 })
    }

    @Test func hides_untilAFetchIsAppliedAfterSending() async {
        let (deletion, recorder) = makeDeletion()
        recorder.holdSend = true
        deletion.stage([1])

        let request = deletion.commit()
        while recorder.gate == nil {
            await Task.yield()
        }
        #expect(deletion.staged.isEmpty)
        #expect(deletion.hides { $0 == 1 })

        recorder.gate?.resume()
        await request?.value
        #expect(deletion.hides { $0 == 1 })
        #expect(recorder.restored.isEmpty)

        deletion.fetchApplied()
        #expect(!deletion.hides { $0 == 1 })
    }

    @Test func reset_whileSending_dropsTheRestore() async {
        let (deletion, recorder) = makeDeletion()
        recorder.holdSend = true
        recorder.failSend = true
        deletion.stage([1])

        let request = deletion.commit()
        while recorder.gate == nil {
            await Task.yield()
        }
        deletion.reset()
        recorder.gate?.resume()
        await request?.value

        #expect(recorder.restored.isEmpty)
        #expect(!deletion.hides { $0 == 1 })
    }

    @Test func reset_dropsWithoutSending() async {
        let (deletion, recorder) = makeDeletion()
        deletion.undoDelay = .milliseconds(100)
        deletion.stage([1])

        deletion.reset()
        await deletion.commitTimer?.value

        #expect(deletion.staged.isEmpty)
        #expect(recorder.sent.isEmpty)
        #expect(recorder.restored.isEmpty)
    }
}
