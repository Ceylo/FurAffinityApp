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

@MainActor
public class OnlineFASession: FASession {
    enum Error: String, Swift.Error {
        case requestFailure
    }
    
    public let username: String
    public let displayUsername: String
    let cookies: [HTTPCookie]
    let dataSource: HTTPDataSource
    
    public init(username: String, displayUsername: String, cookies: [HTTPCookie], dataSource: HTTPDataSource) {
        self.username = username
        self.displayUsername = displayUsername
        self.cookies = cookies
        self.dataSource = dataSource
        self.avatarUrlsCache = try! Storage(
            diskConfig: DiskConfig(name: "AvatarURLs"),
            memoryConfig: MemoryConfig(),
            transformer: TransformerFactory.forCodable(ofType: URL.self)
        )
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
        
        return try? FASubmission(page, url: url)
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
        
        return try? FAJournal(page, url: url)
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
            .map { FANotificationPreview($0) }
        let journalCommentHeaders = page.journalCommentHeaders
            .map { FANotificationPreview($0) }
        let journalHeaders = page.journalHeaders
            .map { FANotificationPreview($0) }

        return .init(
            submissionComments: submissionCommentHeaders,
            journalComments: journalCommentHeaders,
            journals: journalHeaders
        )
    }
    
    // MARK: - Users & avatar
    public func user(for url: URL) async -> FAUser? {
        guard let data = await dataSource.httpData(from: url, cookies: cookies),
              let page = FAUserPage(data: data) else {
            return nil
        }
        return try? FAUser(page)
    }
    
    public func toggleWatch(for user: FAUser) async -> FAUser? {
        guard let watchData = user.watchData else {
            logger.error("Tried to toggle watch on user \(user.name) without watch data")
            return user
        }
        
        _ = await dataSource.httpData(from: watchData.watchUrl, cookies: cookies)
        return await self.user(for: user.name)
    }
    
    private let avatarUrlRequestsQueue = DispatchQueue(label: "FASession.AvatarRequests")
    private var avatarUrlTasks = [String: Task<URL?, Swift.Error>]()
    private let avatarUrlsCache: Storage<String, URL>
    public func avatarUrl(for username: String) async -> URL? {
        guard !username.isEmpty else {
            return nil
        }
        let task = avatarUrlRequestsQueue.sync { () -> Task<URL?, Swift.Error> in
            let previousTask = avatarUrlTasks[username]
            let newTask = Task { () -> URL? in
                _ = await previousTask?.result
                try avatarUrlsCache.removeExpiredObjects()
                
                if let url = try? avatarUrlsCache.object(forKey: username) {
                    return url
                }
                
                guard let user = await user(for: username)
                else { return nil }
                
                let validDays = (7..<14).randomElement()!
                let expiry = Expiry.days(validDays)
                try avatarUrlsCache.setObject(user.avatarUrl, forKey: username, expiry: expiry)
                logger.info("Cached url \(user.avatarUrl, privacy: .public) for user \(username, privacy: .public) for \(validDays) days")
                return user.avatarUrl
            }
            
            avatarUrlTasks[username] = newTask
            return newTask
            
        }
        
        return try? await task.result.get()
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
        
        guard let username = page.username,
              let displayUsername = page.displayUsername
        else {
            logger.error("\(#file, privacy: .public) - missing user")
            return nil
        }
        
        self.init(username: username,
                  displayUsername: displayUsername,
                  cookies: cookies,
                  dataSource: dataSource)
    }
}

