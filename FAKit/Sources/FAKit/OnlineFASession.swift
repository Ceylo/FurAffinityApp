//
//  OnlineFASession.swift
//
//
//  Created by Ceylo on 30/06/2024.
//

import Foundation
import FAPages

public class OnlineFASession: FASession {
    enum Error: LocalizedError, Swift.Error {
        /// A network error
        case requestFailure(underlyingError: LocalizedError)
        
        /// An error caused by failing to parse the received data
        case parsingError(sourceUrl: URL)
        
        /// An error caused by a request made with invalid data
        case internalInconsistency
        
        /// An error with a message provided by furaffinity.net
        case FAErrorResponse(String)
        
        var errorDescription: String? {
            switch self {
            case let .FAErrorResponse(message):
                "The action could not be completed. furaffinity.net provided the following error message:\n\(message)"
            case let .parsingError(sourceUrl):
                "The action could not be completed. The data read from \(sourceUrl) could not be interpreted by the application."
            case let .requestFailure(underlyingError):
                if let underlyingDescription = underlyingError.errorDescription {
                    "The action could not be completed. A network request failed for the following reason: \(underlyingDescription)"
                } else {
                    "The action could not be completed. A network request failed."
                }
            case .internalInconsistency:
                "The action could not be completed. An internal error happened."
            }
        }
    }
    
    public let username: String
    public let displayUsername: String
    private let cookies: [HTTPCookie]
    private let dataSource: HTTPDataSource
    
    public init(
        username: String,
        displayUsername: String,
        cookies: [HTTPCookie],
        dataSource: HTTPDataSource
    ) {
        self.username = username
        self.displayUsername = displayUsername
        self.cookies = cookies
        self.dataSource = dataSource
    }
    
    nonisolated public static func == (lhs: OnlineFASession, rhs: OnlineFASession) -> Bool {
        lhs.username == rhs.username
    }
    
    // MARK: - Submissions feed
    public func submissionPreviews(from sid: Int?) async throws -> [FASubmissionPreview] {
        let url = if let sid {
            FAURLs.submissionsUrl(from: sid)
        } else {
            FAURLs.latest72SubmissionsUrl
        }
        let data = try await dataSource.httpData(from: url, cookies: cookies)
        let page = try FASubmissionsPage(data: data, baseUri: url)
            .unwrap(throwing: Error.parsingError(sourceUrl: url))
        
        let previews = page.submissions
            .compactMap { $0 }
            .map { FASubmissionPreview($0) }
        logger.info("Got \(page.submissions.count) submission previews (\(previews.count) after filter)")
        return previews
    }
    
    public func deleteSubmissionPreviews(_ previews: [FASubmissionPreview]) async throws {
        let url = try FAURLs.submissionsUrl(from: previews.max().unwrap().sid)
        let params: [URLQueryItem] = [
            .init(name: "messagecenter-action", value: "remove_checked")
        ] + previews.map {
            URLQueryItem(name: "submissions[]", value: "\($0.id)")
        }
        
        let data = try await dataSource.httpData(from: url, cookies: cookies, method: .POST, parameters: params)
        guard let page = FASubmissionsPage(data: data, baseUri: url),
              !page.submissions.compactMap({ $0 }).map({ FASubmissionPreview($0) }).contains(previews) else {
            throw Error.parsingError(sourceUrl: url)
        }
    }
    
    public func nukeSubmissions() async throws {
        let url = FAURLs.latest72SubmissionsUrl
        let params: [URLQueryItem] = [
            .init(name: "messagecenter-action", value: "nuke_notifications"),
        ]
        
        let data = try await dataSource.httpData(from: url, cookies: cookies, method: .POST, parameters: params)
        _ = try FASubmissionsPage(data: data, baseUri: url)
            .unwrap(throwing: Error.parsingError(sourceUrl: url))
    }
    
    // MARK: - User gallery
    public func galleryLike(for url: URL) async throws -> FAUserGalleryLike {
        let data = try await dataSource.httpData(from: url, cookies: cookies)
        let page = try FAUserGalleryLikePage(data: data, url: url)
            .unwrap(throwing: Error.parsingError(sourceUrl: url))
        
        let gallery = FAUserGalleryLike(page, url: url)
        logger.info("Got \(page.previews.count) submission previews (\(gallery.previews.count) after filter)")
        return gallery
    }
    
    // MARK: - Submissions
    public func submission(for url: URL) async throws -> FASubmission {
        let data = try await dataSource.httpData(from: url, cookies: cookies)
        let page = try FASubmissionPage(data: data, url: url)
            .unwrap(throwing: Error.parsingError(sourceUrl: url))
        
        return try await FASubmission(page, url: url)
    }
    
    public func toggleFavorite(for submission: FASubmission) async throws -> FASubmission {
        let data = try await dataSource.httpData(from: submission.favoriteUrl, cookies: cookies)
        let page = try FASubmissionPage(data: data, url: submission.url)
            .unwrap(throwing: Error.parsingError(sourceUrl: submission.favoriteUrl))
        
        return try await FASubmission(page, url: submission.url)
    }
    
    public func postComment<C: Commentable>(on commentable: C, replytoCid: Int?, contents: String) async throws -> C {
        let replyToValue = replytoCid.flatMap { "\($0)" } ?? ""
        let params: [URLQueryItem] = [
            .init(name: "f", value: "0"), // Not needed for all commentable types but doesn't harm
            .init(name: "action", value: replytoCid != nil ? "replyto" : "reply"),
            .init(name: "replyto", value: replyToValue),
            .init(name: "reply", value: contents),
            .init(name: "submit", value: "Post Comment")
        ]
        
        let data = try await dataSource.httpData(from: commentable.url, cookies: cookies, method: .POST, parameters: params)
        let page = try await C.PageType(data: data, url: commentable.url)
            .unwrap(throwing: Error.parsingError(sourceUrl: commentable.url))
        
        return try await C(page, url: commentable.url)
    }
    
    // MARK: - Journals
    public func journals(for url: URL) async throws -> FAUserJournals {
        let data = try await dataSource.httpData(from: url, cookies: cookies)
        let page = try FAUserJournalsPage(data: data)
            .unwrap(throwing: Error.parsingError(sourceUrl: url))
        return FAUserJournals(page)
    }
    
    public func journal(for url: URL) async throws -> FAJournal {
        let data = try await dataSource.httpData(from: url, cookies: cookies)
        let page = try FAJournalPage(data: data, url: url)
            .unwrap(throwing: Error.parsingError(sourceUrl: url))
        
        return try await FAJournal(page, url: url)
    }
    
    // MARK: - Notes
    public func notePreviews(from box: NotesBox) async throws -> [FANotePreview] {
        let data = try await dataSource.httpData(from: box.url, cookies: cookies)
        let page = try FANotesPage(data: data)
            .unwrap(throwing: Error.parsingError(sourceUrl: box.url))
        
        let headers = page.noteHeaders
            .compactMap { $0 }
            .map { FANotePreview($0) }
        
        logger.info("Got \(page.noteHeaders.count) note previews (\(headers.count) after filter)")
        return headers
    }
    
    public func note(for url: URL) async throws -> FANote {
        let data = try await dataSource.httpData(from: url, cookies: cookies)
        let page = try FANotePage(data: data)
            .unwrap(throwing: Error.parsingError(sourceUrl: url))
        
        return try await FANote(page, url: url)
    }
    
    public func sendNote(toUsername: String, subject: String, message: String) async throws -> Void {
        guard let newNoteUrl = FAURLs.newNoteUrl(for: toUsername) else {
            logger.error("Failed getting new note url for user \"\(toUsername)\"")
            throw Error.internalInconsistency
        }
        
        let data = try await dataSource.httpData(from: newNoteUrl, cookies: cookies)
        let page = try FANewNotePage(data: data)
            .unwrap(throwing: Error.parsingError(sourceUrl: newNoteUrl))
        
        try await sendNote(
            apiKey: page.apiKey,
            toUsername: toUsername,
            subject: subject,
            message: message
        )
    }
    
    public func sendNote(apiKey: String, toUsername: String, subject: String, message: String) async throws -> Void {
        let url = URL(string: "https://www.furaffinity.net/msg/send/")!
        let params: [URLQueryItem] = [
            .init(name: "key", value: apiKey),
            .init(name: "to", value: toUsername),
            .init(name: "subject", value: subject),
            .init(name: "message", value: message),
        ]
        
        let data = try await dataSource.httpData(from: url, cookies: cookies, method: .POST, parameters: params)
        
        if let errorPage = FASystemErrorPage(data: data) {
            logger.error("Failed sending note: \(errorPage.message)")
            throw Error.FAErrorResponse(errorPage.message)
        }
        
        guard FANotesPage(data: data) != nil else {
            logger.error("Failed sending note")
            throw Error.parsingError(sourceUrl: url)
        }
        
        logger.debug("Note successfully delivered to \(toUsername)")
    }
    
    // MARK: - Notifications
    public func notificationPreviews() async throws -> FANotificationPreviews {
        try await notificationPreviews(method: .GET, parameters: [])
    }
    
    public func deleteSubmissionCommentNotifications(_ notifications: [FANotificationPreview]) async throws -> FANotificationPreviews {
        try await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "remove-submission-comments", value: "Remove Selected Comments"),
        ] + notifications.map {
            URLQueryItem(name: "comments-submissions[]", value: "\($0.id)")
        })
    }
    
    public func deleteJournalCommentNotifications(_ notifications: [FANotificationPreview]) async throws -> FANotificationPreviews {
        try await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "remove-journal-comments", value: "Remove Selected Comments"),
        ] + notifications.map {
            URLQueryItem(name: "comments-journals[]", value: "\($0.id)")
        })
    }
    
    public func deleteShoutNotifications(_ notifications: [FANotificationPreview]) async throws -> FANotificationPreviews {
        try await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "remove-shouts", value: "Remove Selected Shouts"),
        ] + notifications.map {
            URLQueryItem(name: "shouts[]", value: "\($0.id)")
        })
    }
    
    public func deleteJournalNotifications(_ notifications: [FANotificationPreview]) async throws -> FANotificationPreviews {
        try await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "remove-journals", value: "Remove Selected Journals"),
        ] + notifications.map {
            URLQueryItem(name: "journals[]", value: "\($0.id)")
        })
    }
    
    public func nukeAllSubmissionCommentNotifications() async throws -> FANotificationPreviews {
        try await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "nuke-submission-comments", value: "Nuke Submission Comments")
        ])
    }
    
    public func nukeAllJournalCommentNotifications() async throws -> FANotificationPreviews {
        try await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "nuke-journal-comments", value: "Nuke Journal Comments")
        ])
    }
    
    public func nukeAllShoutNotifications() async throws -> FANotificationPreviews {
        try await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "nuke-shouts", value: "Nuke Shouts")
        ])
    }
    
    public func nukeAllJournalNotifications() async throws -> FANotificationPreviews {
        try await notificationPreviews(method: .POST, parameters: [
            URLQueryItem(name: "nuke-journals", value: "Nuke Journals")
        ])
    }
    
    private func notificationPreviews(method: HTTPMethod, parameters: [URLQueryItem]) async throws -> FANotificationPreviews {
        let data = try await dataSource.httpData(from: FAURLs.notificationsUrl, cookies: cookies, method: method, parameters: parameters)
        let page = try FANotificationsPage(data: data)
            .unwrap(throwing: Error.parsingError(sourceUrl: FAURLs.notificationsUrl))
        
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
    
    // MARK: - Users
    public func user(for url: URL) async throws -> FAUser {
        let data = try await dataSource.httpData(from: url, cookies: cookies)
        return try await loadUser(from: data, url: url)
    }
    
    private nonisolated func loadUser(from data: Data, url: URL) async throws -> FAUser {
        let page = try FAUserPage(data: data, url: url).unwrap()
        return try await FAUser(page)
    }
    
    public func toggleWatch(for user: FAUser) async throws -> FAUser {
        guard let watchData = user.watchData else {
            logger.error("Tried to toggle watch on user \(user.name, privacy: .public) without watch data")
            throw Error.internalInconsistency
        }
        
        _ = try await dataSource.httpData(from: watchData.watchUrl, cookies: cookies)
        return try await self.user(for: user.name)
    }
    
    public func watchlist(for username: String, page: Int, direction: FAWatchlist.WatchDirection) async throws -> FAWatchlist {
        let url = FAURLs.watchlistUrl(for: username, page: page, direction: direction)
        let data = try await dataSource.httpData(from: url, cookies: cookies)
        let page = try FAWatchlistPage(data: data, baseUri: url)
            .unwrap(throwing: Error.parsingError(sourceUrl: url))
        
        return FAWatchlist(page)
    }
}

extension OnlineFASession {
    /// Initialize a FASession from the given session cookies.
    /// - Parameter cookies: The cookies for furaffinity.net after the user is logged
    /// in through a usual web browser.
    public convenience init?(cookies: [HTTPCookie], dataSource: HTTPDataSource = URLSession.sharedForFARequests) async {
        guard cookies.map(\.name).contains("a"),
              let data = try? await dataSource.httpData(from: FAURLs.homeUrl, cookies: cookies)
        else {
            return nil
        }
        
        guard let page = FAHomePage(data: data, baseUri: FAURLs.homeUrl) else {
            logger.info("User is not logged in")
            return nil
        }
        logger.info("User is logged in")
        
        self.init(
            username: page.username,
            displayUsername: page.displayUsername,
            cookies: cookies,
            dataSource: dataSource
        )
    }
}

