//
//  ModelTests.swift
//  FurAffinityTests
//

import FAKit
import Foundation
import Testing

@testable import Fur_Affinity

@MainActor
struct ModelTests {
    // MARK: - Helpers

    func makeSubmission(
        id: Int = 1,
        author: String = "author",
        display: String? = nil,
        title: String = "Submission Title"
    ) -> FASubmissionPreview {
        .init(
            sid: id,
            url: URL(string: "https://www.furaffinity.net/view/\(1000 + id)/")!,
            thumbnailUrl: URL(string: "https://t.furaffinity.net/\(1000 + id)@200-1637084699.jpg")!,
            thumbnailWidthOnHeightRatio: 1.0,
            title: title,
            author: author,
            displayAuthor: display ?? author.capitalized,
            rating: .general
        )
    }

    func makeNote(
        id: Int = 1,
        author: String = "author",
        display: String? = nil,
        title: String = "Note Title",
        unread: Bool = true
    ) -> FANotePreview {
        .init(
            id: id,
            author: author,
            displayAuthor: display ?? author.capitalized,
            title: title,
            datetime: "now",
            naturalDatetime: "now",
            unread: unread,
            noteUrl: URL(string: "https://www.furaffinity.net/msg/pms/1/\(id)/#message")!
        )
    }

    // MARK: - Tests

    @Test func fetchSubmissionPreviews_populatesSubmissionPreviews() async throws {
        let mock = MockFASession(
            mockSubmissionPreviews: [makeSubmission(id: 1), makeSubmission(id: 2)]
        )
        let model = Model()
        try await model.setSession(mock)
        // processNewSession() already called fetchSubmissionPreviews(); reset by
        // replacing previews state via another fetch to confirm idempotency,
        // but the main assertion is that the count is correct after setSession.
        #expect(model.submissionPreviews?.count == 2)
    }

    @Test func unreadInboxNoteCount_countsOnlyUnreadNotes() async throws {
        let mock = MockFASession(
            mockNotePreviews: [
                makeNote(id: 1, unread: true),
                makeNote(id: 2, unread: false),
                makeNote(id: 3, unread: true)
            ]
        )
        let model = Model()
        try await model.setSession(mock)
        // processNewSession() already called fetchNotePreviews(from: .inbox)
        #expect(model.unreadInboxNoteCount == 2)
    }

    @Test func processNewSession_clearsNoteBadgeOnLogout() async throws {
        let mock = MockFASession(
            mockNotePreviews: [makeNote(id: 1, unread: true), makeNote(id: 2, unread: true)]
        )
        let model = Model()
        try await model.setSession(mock)
        #expect(model.displayedUnreadNoteCount == 2)

        // Logout resets the Notes badge to 0 (item 1 regression guard).
        try await model.setSession(nil)
        #expect(model.displayedUnreadNoteCount == 0)
    }

    @Test func markNoteAsReadLocally_updatesNoteBadge() async throws {
        let mock = MockFASession(
            mockNotePreviews: [makeNote(id: 1, unread: true), makeNote(id: 2, unread: true)]
        )
        let model = Model()
        try await model.setSession(mock)
        #expect(model.displayedUnreadNoteCount == 2)

        // Reading a note must refresh the badge immediately (item 2 regression guard).
        let read = FANote(
            url: URL(string: "https://www.furaffinity.net/msg/pms/1/1/#message")!,
            author: "author",
            displayAuthor: "Author",
            title: "Note Title",
            datetime: "now",
            naturalDatetime: "now",
            message: AttributedString(),
            messageWithoutWarning: AttributedString(),
            answerKey: "",
            answerPlaceholderMessage: ""
        )
        model.markNoteAsReadLocally(read)
        #expect(model.displayedUnreadNoteCount == 1)
    }

    @Test func shouldAutoRefresh_returnsFalseWhenRecentlyRefreshed() {
        #expect(Model.shouldAutoRefresh(with: Date()) == false)
        #expect(Model.shouldAutoRefresh(with: nil) == true)
        #expect(Model.shouldAutoRefresh(with: Date.distantPast) == true)
    }

    @Test func deleteSubmissionPreviews_rollsBackOnFailure() async throws {
        let mock = MockFASession(
            mockSubmissionPreviews: [makeSubmission(id: 1), makeSubmission(id: 2)]
        )
        let model = Model()
        try await model.setSession(mock)
        #expect(model.submissionPreviews?.count == 2)

        // Make the next deletion fail, then trigger the deletion
        mock.shouldDeleteFail = true
        let previews = Array(model.submissionPreviews!)
        model.deleteSubmissionPreviews(previews)

        // Immediately after the optimistic removal, count should be 0
        #expect(model.submissionPreviews?.count == 0)

        // Wait for the background Task to complete and roll back
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(model.submissionPreviews?.count == 2)
    }

    private func makeModelWithSubmissions(_ ids: [Int]) async throws -> (Model, MockFASession) {
        let mock = MockFASession(mockSubmissionPreviews: ids.map { makeSubmission(id: $0) })
        let model = Model()
        try await model.setSession(mock)
        return (model, mock)
    }

    @Test func stageSubmissionPreviewsDeletion_removesRowsWithoutSessionCall() async throws {
        let (model, mock) = try await makeModelWithSubmissions([3, 2, 1])
        let staged = model.submissionPreviews![1]

        model.stageSubmissionPreviewsDeletion([staged])

        #expect(model.submissionPreviews?.map(\.sid) == [3, 1])
        #expect(model.stagedSubmissionPreviewsDeletion == [staged])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(mock.deletedSubmissionPreviewBatches.isEmpty)
    }

    @Test func fetchSubmissionPreviews_doesNotBringBackStagedRows() async throws {
        let (model, _) = try await makeModelWithSubmissions([3, 2, 1])
        // The newest row: once it's gone, a fetch would otherwise see it as new.
        let staged = model.submissionPreviews![0]
        model.stageSubmissionPreviewsDeletion([staged])

        _ = try await model.fetchSubmissionPreviews()
        _ = try await model.fetchSubmissionPreviews()

        #expect(model.submissionPreviews?.map(\.sid) == [2, 1])
        #expect(model.stagedSubmissionPreviewsDeletion == [staged])
    }

    @Test func undoStagedSubmissionPreviewsDeletion_restoresOrder() async throws {
        let (model, mock) = try await makeModelWithSubmissions([4, 3, 2, 1])
        model.stageSubmissionPreviewsDeletion([model.submissionPreviews![1], model.submissionPreviews![3]])
        #expect(model.submissionPreviews?.map(\.sid) == [4, 2])

        model.undoStagedSubmissionPreviewsDeletion()

        #expect(model.submissionPreviews?.map(\.sid) == [4, 3, 2, 1])
        #expect(model.stagedSubmissionPreviewsDeletion.isEmpty)
        #expect(model.commitStagedSubmissionPreviewsDeletion() == nil)
        #expect(mock.deletedSubmissionPreviewBatches.isEmpty)
    }

    @Test func commitStagedSubmissionPreviewsDeletion_callsSession() async throws {
        let (model, mock) = try await makeModelWithSubmissions([3, 2, 1])
        let staged = model.submissionPreviews![1]
        model.stageSubmissionPreviewsDeletion([staged])

        await model.commitStagedSubmissionPreviewsDeletion()?.value

        #expect(mock.deletedSubmissionPreviewBatches == [[staged]])
        #expect(model.stagedSubmissionPreviewsDeletion.isEmpty)
        #expect(model.submissionPreviews?.map(\.sid) == [3, 1])
    }

    @Test func commitStagedSubmissionPreviewsDeletion_rollsBackOnFailure() async throws {
        let (model, mock) = try await makeModelWithSubmissions([3, 2, 1])
        mock.shouldDeleteFail = true
        model.stageSubmissionPreviewsDeletion([model.submissionPreviews![1]])

        await model.commitStagedSubmissionPreviewsDeletion()?.value

        #expect(mock.deletedSubmissionPreviewBatches.count == 1)
        #expect(model.submissionPreviews?.map(\.sid) == [3, 2, 1])
    }

    @Test func stageSubmissionPreviewsDeletion_commitsAfterUndoDelay() async throws {
        let (model, mock) = try await makeModelWithSubmissions([3, 2, 1])
        model.stagedDeletionUndoDelay = .seconds(1)
        let undone = model.submissionPreviews![0]
        let staged = model.submissionPreviews![1]

        // An undone batch's countdown must not commit the next one early. Nothing
        // suspends before the await, so its timer runs with `staged` already staged.
        model.stageSubmissionPreviewsDeletion([undone])
        let undoneTimer = model.stagedDeletionCommitTimer
        model.undoStagedSubmissionPreviewsDeletion()
        model.stageSubmissionPreviewsDeletion([staged])
        await undoneTimer?.value
        #expect(mock.deletedSubmissionPreviewBatches.isEmpty)

        await model.stagedDeletionCommitTimer?.value
        #expect(mock.deletedSubmissionPreviewBatches == [[staged]])
        #expect(model.stagedSubmissionPreviewsDeletion.isEmpty)
    }

    @Test func stageSubmissionPreviewsDeletion_commitsPreviousBatch() async throws {
        let (model, mock) = try await makeModelWithSubmissions([3, 2, 1])
        let first = model.submissionPreviews![0]
        let second = model.submissionPreviews![2]

        model.stageSubmissionPreviewsDeletion([first])
        model.stageSubmissionPreviewsDeletion([second])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(mock.deletedSubmissionPreviewBatches == [[first]])
        #expect(model.stagedSubmissionPreviewsDeletion == [second])
        #expect(model.submissionPreviews?.map(\.sid) == [2])
    }

    @Test func defaultsWriteFromBackgroundDoesNotCrashModelObservers() async {
        // Model.init runs two @MainActor loops over Defaults.updates (the Defaults
        // library observes the standard suite via KVO). Writing an observed key off the
        // main actor synchronously flushes CFPrefs KVO on that thread; before the fix
        // this entered the main-actor observer off-main and aborted the process via the
        // executor-isolation assertion.
        //
        // The key is written through raw UserDefaults (rather than the Defaults API) so
        // the test target doesn't need to link the Defaults package — Defaults observes
        // the same KVO either way. Name must match
        // Defaults.Keys.latestSubmissionNotificationID in UserDefaultKeys.swift.
        let keyName = "latestSubmissionNotificationID"
        let defaults = UserDefaults.standard
        let model = Model()
        let original = defaults.object(forKey: keyName)
        defer { defaults.set(original, forKey: keyName) }

        // Off-main write with a guaranteed-changed value so KVO actually fires.
        let newValue = (original as? Int ?? 0) &+ 1
        await Task.detached {
            UserDefaults.standard.set(newValue, forKey: keyName)
        }.value

        // Keep observers alive across the write. Reaching here without aborting
        // means the event was delivered safely on the main actor.
        withExtendedLifetime(model) {}
    }
}
