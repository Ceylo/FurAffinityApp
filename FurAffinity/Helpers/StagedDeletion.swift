//
//  StagedDeletion.swift
//  FurAffinity
//
//  Created by Ceylo on 19/10/2026.
//

// SwiftUI rather than Observation: on Android an @Observable only recomposes with
// SkipAndroidBridge visible, which SwiftUI brings.
import SwiftUI

@MainActor @Observable
final class StagedDeletion<Item: Hashable> {
    private(set) var staged = [Item]()
    /// How long a staged deletion can be undone before it is committed.
    @ObservationIgnored var undoDelay: Duration = .seconds(5)
    /// Finishes once the deletion it commits has been sent. Not private so tests can await it.
    @ObservationIgnored private(set) var commitTimer: Task<Void, Never>?
    @ObservationIgnored private var sending = Set<Item>()
    private let send: @MainActor ([Item]) async throws -> Void
    private let restore: @MainActor ([Item]) -> Void

    init(send: @escaping @MainActor ([Item]) async throws -> Void,
         restore: @escaping @MainActor ([Item]) -> Void) {
        self.send = send
        self.restore = restore
    }

    func stage(_ items: [Item]) {
        commit()
        staged = items
        #if FA_SKIP_MODULE
        // Android's snackbar honours the "Time to take action" setting, as Material's does.
        let delay = AndroidAccessibility.recommendedTimeout(undoDelay)
        #else
        let delay = undoDelay
        #endif
        commitTimer = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await commit()?.value
        }
        logger.info("Staged deletion of \(items.count) items")
    }

    /// - Returns: the deletion request, rolled back if it fails; `nil` if nothing was staged.
    @discardableResult
    func commit() -> Task<Void, Never>? {
        guard let items = takeStaged() else { return nil }
        sending.formUnion(items)
        logger.info("Committing deletion of \(items.count) items")

        return Task {
            do {
                try await send(items)
            } catch {
                logger.error("Deletion of \(items.count) items failed with error \"\(error)\", rolling back")
                restore(items)
            }
            sending.subtract(items)
        }
    }

    func undo() {
        takeStaged().map(restore)
    }

    func hides(where predicate: (Item) -> Bool) -> Bool {
        staged.contains(where: predicate) || sending.contains(where: predicate)
    }

    private func takeStaged() -> [Item]? {
        commitTimer?.cancel()
        guard !staged.isEmpty else { return nil }
        defer { staged = [] }
        return staged
    }

    func reset() {
        commitTimer?.cancel()
        staged = []
        sending = []
    }
}
