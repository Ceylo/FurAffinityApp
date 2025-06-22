//
//  FASession.swift
//
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation
import FAPages

public struct FANotificationPreviews: Equatable, Sendable {
    public let submissionComments: [FANotificationPreview]
    public let journalComments: [FANotificationPreview]
    public let shouts: [FANotificationPreview]
    public let journals: [FANotificationPreview]
    
    public init(
        submissionComments: [FANotificationPreview],
        journalComments: [FANotificationPreview],
        shouts: [FANotificationPreview],
        journals: [FANotificationPreview]
    ) {
        self.submissionComments = submissionComments
        self.journalComments = journalComments
        self.shouts = shouts
        self.journals = journals
    }
    
    public init() {
        self.submissionComments = []
        self.journalComments = []
        self.shouts = []
        self.journals = []
    }
}

@MainActor
public protocol FASession: AnyObject, Equatable {
    var username: String { get }
    var displayUsername: String { get }
    
    // MARK: - Submissions feed
    
    /// - Parameter sid: The first submission ID (in date order) that should be returned.
    /// If `nil`, the latest submission previews are provided.
    func submissionPreviews(from sid: Int?) async -> [FASubmissionPreview]
    func nukeSubmissions() async throws
    
    // MARK: - User gallery
    func galleryLike(for url: URL) async throws -> FAUserGalleryLike
    
    // MARK: - Submissions
    func submission(for url: URL) async throws -> FASubmission
    func toggleFavorite(for submission: FASubmission) async throws -> FASubmission
    func postComment<C: Commentable>(on commentable: C, replytoCid: Int?, contents: String) async throws -> C
    
    // MARK: - Journals
    func journals(for url: URL) async throws -> FAUserJournals
    func journal(for url: URL) async throws -> FAJournal
    
    // MARK: - Notes
    func notePreviews() async -> [FANotePreview]
    func note(for url: URL) async throws -> FANote
    func sendNote(toUsername: String, subject: String, message: String) async throws -> Void
    func sendNote(apiKey: String, toUsername: String, subject: String, message: String) async throws -> Void
    
    // MARK: - Notifications
    func notificationPreviews() async -> FANotificationPreviews
    func deleteSubmissionPreviews(_ previews: [FASubmissionPreview]) async throws
    func deleteSubmissionCommentNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews
    func deleteJournalCommentNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews
    func deleteShoutNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews
    func deleteJournalNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews
    func nukeAllSubmissionCommentNotifications() async -> FANotificationPreviews
    func nukeAllJournalCommentNotifications() async -> FANotificationPreviews
    func nukeAllShoutNotifications() async -> FANotificationPreviews
    func nukeAllJournalNotifications() async -> FANotificationPreviews
    
    // MARK: - Users
    func user(for url: URL) async throws -> FAUser
    func toggleWatch(for user: FAUser) async throws -> FAUser
    func watchlist(for username: String, direction: FAWatchlist.WatchDirection) async throws -> FAWatchlist
}

extension FASession {
    public func galleryLike(for user: String) async throws -> FAUserGalleryLike {
        try await galleryLike(for: FAURLs.galleryUrl(for: user))
    }
    
    public func submission(for preview: FASubmissionPreview) async throws -> FASubmission {
        try await submission(for: preview.url)
    }
    
    public func journal(for preview: FANotificationPreview) async throws -> FAJournal {
        try await journal(for: preview.url)
    }
    
    public func note(for preview: FANotePreview) async throws -> FANote {
        try await note(for: preview.noteUrl)
    }
    
    public func user(for username: String) async throws -> FAUser {
        let userpageUrl = try FAURLs.userpageUrl(for: username)
        return try await user(for: userpageUrl)
    }
    
    public func watchlist(for url: URL) async throws -> FAWatchlist {
        let parsed = try FAURLs.parseWatchlistUrl(url).unwrap()
        return try await watchlist(for: parsed.username, direction: parsed.watchDirection)
    }
}
