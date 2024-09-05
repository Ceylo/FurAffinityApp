//
//  OnlineFASession.swift
//
//
//  Created by Ceylo on 30/06/2024.
//

import Foundation
import FAPages
import Cache

private extension Expiry {
    static func days(_ days: Int) -> Expiry {
        .seconds(TimeInterval(60 * 60 * 24 * days))
    }
}

public class OnlineFASession: FASession, AvatarCacheDelegate {
    enum Error: String, Swift.Error {
        case requestFailure
    }
    
    public let username: String
    public let displayUsername: String
    public let avatarUrl: URL
    private let cookies: [HTTPCookie]
    private let dataSource: HTTPDataSource
    private var avatarCache: AvatarCache!
    
    public init(
        username: String,
        displayUsername: String,
        avatarUrl: URL,
        cookies: [HTTPCookie],
        dataSource: HTTPDataSource
    ) {
        self.username = username
        self.displayUsername = displayUsername
        self.avatarUrl = avatarUrl
        self.cookies = cookies
        self.dataSource = dataSource
        self.avatarCache = .init(delegate: self)
    }
    
    nonisolated public static func == (lhs: OnlineFASession, rhs: OnlineFASession) -> Bool {
        lhs.username == rhs.username
    }
    
    // MARK: - Submissions feed
    public func submissionPreviews() async -> [FASubmissionPreview] {
        let url = FAURLs.latest72SubmissionsUrl
        guard let data = await dataSource.httpData(from: url, cookies: cookies),
              let page = await FASubmissionsPage(data: data, baseUri: url)
        else { return [] }
        
        let previews = page.submissions
            .compactMap { $0 }
            .map { FASubmissionPreview($0) }
        logger.info("Got \(page.submissions.count) submission previews (\(previews.count) after filter)")
        return previews
    }
    
    public func nukeSubmissions() async throws {
        let url = FAURLs.latest72SubmissionsUrl
        let params: [URLQueryItem] = [
            .init(name: "messagecenter-action", value: "nuke_notifications"),
        ]
        
        guard let data = await dataSource.httpData(from: url, cookies: cookies, method: .POST, parameters: params),
              await FASubmissionsPage(data: data, baseUri: url) != nil else {
            throw Error.requestFailure
        }
    }
    
    // MARK: - User gallery
    public func galleryLike(for url: URL) async -> FAUserGalleryLike? {
        guard let data = await dataSource.httpData(from: url, cookies: cookies),
              let page = await FAUserGalleryLikePage(data: data)
        else { return nil }
        
        let gallery = FAUserGalleryLike(page)
        logger.info("Got \(page.previews.count) submission previews (\(gallery.previews.count) after filter)")
        return gallery
    }
    
    // MARK: - Submissions
    public func submission(for url: URL) async -> FASubmission? {
        guard let data = await dataSource.httpData(from: url, cookies: cookies),
              let page = FASubmissionPage(data: data)
        else { return nil }
        
        let submission = try? FASubmission(page, url: url)
        if let submission {
            Task {
                await cacheAvatars(from: submission)
            }
        }
        return submission
    }
    
    public func toggleFavorite(for submission: FASubmission) async -> FASubmission? {
        guard let data = await dataSource.httpData(from: submission.favoriteUrl, cookies: cookies),
              let page = FASubmissionPage(data: data)
        else { return nil }
        
        return try? FASubmission(page, url: submission.url)
    }
    
    public func postComment<C: Commentable>(on commentable: C, replytoCid: Int?, contents: String) async -> C? {
        let replyToValue = replytoCid.flatMap { "\($0)" } ?? ""
        let params: [URLQueryItem] = [
            .init(name: "f", value: "0"), // Not needed for all commentable types but doesn't harm
            .init(name: "action", value: replytoCid != nil ? "replyto" : "reply"),
            .init(name: "replyto", value: replyToValue),
            .init(name: "reply", value: contents),
            .init(name: "submit", value: "Post Comment")
        ]
        
        guard let data = await dataSource.httpData(from: commentable.url, cookies: cookies, method: .POST, parameters: params),
              let page = C.PageType(data: data)
        else { return nil }
        
        return try? C(page, url: commentable.url)
    }
    
    // MARK: - Journals
    public func journal(for url: URL) async -> FAJournal? {
        guard let data = await dataSource.httpData(from: url, cookies: cookies),
              let page = FAJournalPage(data: data)
        else { return nil }
        
        
        let journal = try? FAJournal(page, url: url)
        if let journal {
            Task {
                await cacheAvatars(from: journal)
            }
        }
        return journal
    }
    
    // MARK: - Notes
    public func notePreviews() async -> [FANotePreview] {
        guard let data = await dataSource.httpData(from: FAURLs.notesInboxUrl, cookies: cookies),
              let page = await FANotesPage(data: data)
        else { return [] }
        
        let headers = page.noteHeaders
            .compactMap { $0 }
            .map { FANotePreview($0) }
        
        logger.info("Got \(page.noteHeaders.count) note previews (\(headers.count) after filter)")
        return headers
    }
    
    public func note(for url: URL) async -> FANote? {
        guard let data = await dataSource.httpData(from: url, cookies: cookies),
              let page = FANotePage(data: data)
        else { return nil }
        
        return try? FANote(page)
    }
    
    // MARK: - Notifications
    public func notificationPreviews() async -> FANotificationPreviews {
        await notificationPreviews(method: .GET, parameters: [])
    }
    
    public func deleteSubmissionCommentNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews {
        await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "remove-submission-comments", value: "Remove Selected Comments"),
        ] + notifications.map {
            URLQueryItem(name: "comments-submissions[]", value: "\($0.id)")
        })
    }
    
    public func deleteJournalCommentNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews {
        await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "remove-journal-comments", value: "Remove Selected Comments"),
        ] + notifications.map {
            URLQueryItem(name: "comments-journals[]", value: "\($0.id)")
        })
    }
    
    public func deleteShoutNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews {
        await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "remove-shouts", value: "Remove Selected Shouts"),
        ] + notifications.map {
            URLQueryItem(name: "shouts[]", value: "\($0.id)")
        })
    }
    
    public func deleteJournalNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews {
        await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "remove-journals", value: "Remove Selected Journals"),
        ] + notifications.map {
            URLQueryItem(name: "journals[]", value: "\($0.id)")
        })
    }
    
    public func nukeAllSubmissionCommentNotifications() async -> FANotificationPreviews {
        await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "nuke-submission-comments", value: "Nuke Submission Comments")
        ])
    }
    
    public func nukeAllJournalCommentNotifications() async -> FANotificationPreviews {
        await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "nuke-journal-comments", value: "Nuke Journal Comments")
        ])
    }
    
    public func nukeAllShoutNotifications() async -> FANotificationPreviews {
        await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "nuke-shouts", value: "Nuke Shouts")
        ])
    }
    
    public func nukeAllJournalNotifications() async -> FANotificationPreviews {
        await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "nuke-journals", value: "Nuke Journals")
        ])
    }
    
    private func notificationPreviews(method: HTTPMethod, parameters: [URLQueryItem]) async -> FANotificationPreviews {
        guard let data = await dataSource.httpData(from: FAURLs.notificationsUrl, cookies: cookies, method: method, parameters: parameters),
              let page = await FANotificationsPage(data: data)
        else { return .init() }
        
        let notificationCount = page.submissionCommentHeaders.count + page.journalCommentHeaders.count + page.journalHeaders.count
        logger.info("Got \(notificationCount) notification previews")
        
        let submissionCommentHeaders = page.submissionCommentHeaders
            .map(FANotificationPreview.init)
        let journalCommentHeaders = page.journalCommentHeaders
            .map(FANotificationPreview.init)
        let shoutHeaders = page.shoutHeaders
            .map(FANotificationPreview.init)
        let journalHeaders = page.journalHeaders
            .map(FANotificationPreview.init)

        return .init(
            submissionComments: submissionCommentHeaders,
            journalComments: journalCommentHeaders,
            shouts: shoutHeaders,
            journals: journalHeaders
        )
    }
    
    // MARK: - Users & avatar
    public func user(for url: URL) async -> FAUser? {
        guard let data = await dataSource.httpData(from: url, cookies: cookies),
              let page = FAUserPage(data: data) else {
            return nil
        }
        let user = try? FAUser(page)
        if let user {
            Task {
                await cacheAvatars(from: user)
            }
        }
        return user
    }
    
    public func toggleWatch(for user: FAUser) async -> FAUser? {
        guard let watchData = user.watchData else {
            logger.error("Tried to toggle watch on user \(user.name) without watch data")
            return user
        }
        
        _ = await dataSource.httpData(from: watchData.watchUrl, cookies: cookies)
        return await self.user(for: user.name)
    }
    
    public func watchlist(for username: String, direction: FAWatchlist.WatchDirection) async -> FAWatchlist? {
        let url = FAURLs.watchlistUrl(for: username, direction: direction)        
        guard let data = await dataSource.httpData(from: url, cookies: cookies),
              let page = await FAWatchlistPage(data: data, baseUri: url) else {
            return nil
        }
        
        return FAWatchlist(page)
    }
    
    public func avatarUrl(for username: String) async -> URL? {
        await avatarCache.avatarUrl(for: username)
    }
    
    private nonisolated func cacheAvatars(from submission: FASubmission) async {
        try? await avatarCache.cacheAvatarUrl(submission.authorAvatarUrl, for: submission.author)
        await cacheAvatars(from: submission.comments)
    }
    
    private nonisolated func cacheAvatars(from journal: FAJournal) async {
        try? await avatarCache.cacheAvatarUrl(journal.authorAvatarUrl, for: journal.author)
        await cacheAvatars(from: journal.comments)
    }
    
    private nonisolated func cacheAvatars(from user: FAUser) async {
        try? await avatarCache.cacheAvatarUrl(user.avatarUrl, for: user.name)
        await cacheAvatars(from: user.shouts)
    }
    
    private nonisolated func cacheAvatars(from comments: [FAComment]) async {
        try? await comments.forEach { comment in
            if case let .visible(comment) = comment {
                try await avatarCache.cacheAvatarUrl(comment.authorAvatarUrl, for: comment.author)
            }
        }
    }
}

extension OnlineFASession {
    /// Initialize a FASession from the given session cookies.
    /// - Parameter cookies: The cookies for furaffinity.net after the user is logged
    /// in through a usual web browser.
    public convenience init?(cookies: [HTTPCookie], dataSource: HTTPDataSource = URLSession.sharedForFARequests) async {
        guard cookies.map(\.name).contains("a"),
              let data = await dataSource.httpData(from: FAURLs.homeUrl, cookies: cookies),
              let page = FAHomePage(data: data, baseUri: FAURLs.homeUrl)
        else { return nil }
        
        self.init(
            username: page.username,
            displayUsername: page.displayUsername,
            avatarUrl: page.avatarUrl,
            cookies: cookies,
            dataSource: dataSource
        )
    }
}

