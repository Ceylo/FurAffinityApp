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

    @Test func defaultsWriteFromBackgroundDoesNotCrashModelObservers() async {
        // Model.init registers two @MainActor Defaults.publisher sinks (the Defaults
        // library observes the standard suite via KVO). Writing an observed key off the
        // main actor synchronously flushes CFPrefs KVO on that thread; before the fix
        // this entered the main-actor sink off-main and aborted the process via the
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
        // means the sink was delivered safely on the main actor.
        withExtendedLifetime(model) {}
    }
}
