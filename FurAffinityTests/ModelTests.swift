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
            displayAuthor: display ?? author.capitalized
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
}
