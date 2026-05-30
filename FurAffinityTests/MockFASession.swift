//
//  MockFASession.swift
//  FurAffinityTests
//

import Foundation
import FAKit

@testable import Fur_Affinity

@MainActor
final class MockFASession: FASession {
    let username: String
    let displayUsername: String

    var mockSubmissionPreviews: [FASubmissionPreview]
    var mockNotePreviews: [FANotePreview]
    var mockNotificationPreviews: FANotificationPreviews
    var shouldDeleteFail: Bool

    nonisolated static func == (lhs: MockFASession, rhs: MockFASession) -> Bool {
        lhs === rhs
    }

    init(
        username: String = "testuser",
        mockSubmissionPreviews: [FASubmissionPreview] = [],
        mockNotePreviews: [FANotePreview] = [],
        mockNotificationPreviews: FANotificationPreviews = FANotificationPreviews(),
        shouldDeleteFail: Bool = false
    ) {
        self.username = username
        self.displayUsername = username
        self.mockSubmissionPreviews = mockSubmissionPreviews
        self.mockNotePreviews = mockNotePreviews
        self.mockNotificationPreviews = mockNotificationPreviews
        self.shouldDeleteFail = shouldDeleteFail
    }

    // MARK: - Submissions feed

    func submissionPreviews(from sid: Int?) async throws -> [FASubmissionPreview] {
        mockSubmissionPreviews
    }

    func nukeSubmissions() async throws {}

    // MARK: - User gallery

    func galleryLike(for url: URL) async throws -> FAUserGalleryLike {
        throw ModelError.disconnected
    }

    // MARK: - Submissions

    func submission(for url: URL) async throws -> FASubmission {
        throw ModelError.disconnected
    }

    func toggleFavorite(for submission: FASubmission) async throws -> FASubmission {
        throw ModelError.disconnected
    }

    func postComment<C: Commentable>(on commentable: C, replytoCid: Int?, contents: String) async throws -> C {
        throw ModelError.disconnected
    }

    // MARK: - Journals

    func journals(for url: URL) async throws -> FAUserJournals {
        throw ModelError.disconnected
    }

    func journal(for url: URL) async throws -> FAJournal {
        throw ModelError.disconnected
    }

    // MARK: - Notes

    func notePreviews(from box: NotesBox) async throws -> [FANotePreview] {
        mockNotePreviews
    }

    func note(for url: URL) async throws -> FANote {
        throw ModelError.disconnected
    }

    func sendNote(toUsername: String, subject: String, message: String) async throws {}

    func sendNote(apiKey: String, toUsername: String, subject: String, message: String) async throws {}

    func moveNotes(_ notes: [FANotePreview], to box: NotesBox) async throws -> [FANotePreview] {
        notes
    }

    func markNotesAsUnread(_ notes: [FANotePreview]) async throws -> [FANotePreview] {
        notes
    }

    // MARK: - Notifications

    func notificationPreviews() async throws -> FANotificationPreviews {
        mockNotificationPreviews
    }

    func deleteSubmissionPreviews(_ previews: [FASubmissionPreview]) async throws {
        if shouldDeleteFail {
            throw ModelError.disconnected
        }
    }

    func deleteSubmissionCommentNotifications(_ notifications: [FANotificationPreview]) async throws -> FANotificationPreviews {
        mockNotificationPreviews
    }

    func deleteJournalCommentNotifications(_ notifications: [FANotificationPreview]) async throws -> FANotificationPreviews {
        mockNotificationPreviews
    }

    func deleteShoutNotifications(_ notifications: [FANotificationPreview]) async throws -> FANotificationPreviews {
        mockNotificationPreviews
    }

    func deleteJournalNotifications(_ notifications: [FANotificationPreview]) async throws -> FANotificationPreviews {
        mockNotificationPreviews
    }

    func nukeAllSubmissionCommentNotifications() async throws -> FANotificationPreviews {
        mockNotificationPreviews
    }

    func nukeAllJournalCommentNotifications() async throws -> FANotificationPreviews {
        mockNotificationPreviews
    }

    func nukeAllShoutNotifications() async throws -> FANotificationPreviews {
        mockNotificationPreviews
    }

    func nukeAllJournalNotifications() async throws -> FANotificationPreviews {
        mockNotificationPreviews
    }

    // MARK: - Users

    func user(for url: URL) async throws -> FAUser {
        throw ModelError.disconnected
    }

    func toggleWatch(for user: FAUser) async throws -> FAUser {
        throw ModelError.disconnected
    }

    func watchlist(for username: String, page: Int, direction: FAWatchlist.WatchDirection) async throws -> FAWatchlist {
        throw ModelError.disconnected
    }
}
