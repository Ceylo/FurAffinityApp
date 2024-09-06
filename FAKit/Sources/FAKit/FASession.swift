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

public protocol AvatarProvider: Actor {
    func avatarUrl(for username: String) async -> URL?
}

@MainActor
public protocol FASession: AnyObject, Equatable {
    var username: String { get }
    var displayUsername: String { get }
    var avatarUrl: URL { get }
    var avatarProvider: AvatarProvider { get }
    
    // MARK: - Submissions feed
    func submissionPreviews() async -> [FASubmissionPreview]
    func nukeSubmissions() async throws
    
    // MARK: - User gallery
    func galleryLike(for url: URL) async -> FAUserGalleryLike?
    
    // MARK: - Submissions
    func submission(for url: URL) async -> FASubmission?
    func toggleFavorite(for submission: FASubmission) async -> FASubmission?
    func postComment<C: Commentable>(on commentable: C, replytoCid: Int?, contents: String) async -> C?
    
    // MARK: - Journals
    func journal(for url: URL) async -> FAJournal?
    
    // MARK: - Notes
    func notePreviews() async -> [FANotePreview]
    func note(for url: URL) async -> FANote?
    
    // MARK: - Notifications
    func notificationPreviews() async -> FANotificationPreviews
    func deleteSubmissionCommentNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews
    func deleteJournalCommentNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews
    func deleteShoutNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews
    func deleteJournalNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews
    func nukeAllSubmissionCommentNotifications() async -> FANotificationPreviews
    func nukeAllJournalCommentNotifications() async -> FANotificationPreviews
    func nukeAllShoutNotifications() async -> FANotificationPreviews
    func nukeAllJournalNotifications() async -> FANotificationPreviews
    
    // MARK: - Users & avatar
    func user(for url: URL) async -> FAUser?
    func toggleWatch(for user: FAUser) async -> FAUser?
    func watchlist(for username: String, direction: FAWatchlist.WatchDirection) async -> FAWatchlist?
    func avatarUrl(for username: String) async -> URL?
}

extension FASession {
    public func galleryLike(for user: String) async -> FAUserGalleryLike? {
        await galleryLike(for: FAURLs.galleryUrl(for: user))
    }
    
    public func submission(for preview: FASubmissionPreview) async -> FASubmission? {
        await submission(for: preview.url)
    }
    
    public func journal(for preview: FANotificationPreview) async -> FAJournal? {
        await journal(for: preview.url)
    }
    
    public func note(for preview: FANotePreview) async -> FANote? {
        await note(for: preview.noteUrl)
    }
    
    public func user(for username: String) async -> FAUser? {
        guard let userpageUrl = FAURLs.userpageUrl(for: username) else {
            return nil
        }
        return await user(for: userpageUrl)
    }
    
    public func watchlist(for url: URL) async -> FAWatchlist? {
        guard let parsed = FAURLs.parseWatchlistUrl(url) else {
            return nil
        }
        
        return await watchlist(for: parsed.username, direction: parsed.watchDirection)
    }
}
