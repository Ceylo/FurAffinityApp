//
//  FASession.swift
//
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation
import FAPages

open class FASession: Equatable {
    public let username: String
    public let displayUsername: String
    let cookies: [HTTPCookie]
    let dataSource: HTTPDataSource
    
    public init(username: String, displayUsername: String, cookies: [HTTPCookie], dataSource: HTTPDataSource) {
        self.username = username
        self.displayUsername = displayUsername
        self.cookies = cookies
        self.dataSource = dataSource
    }
    
    public static func == (lhs: FASession, rhs: FASession) -> Bool {
        lhs.username == rhs.username
    }
    
    open func submissionPreviews() async -> [FASubmissionPreview] {
        guard let data = await dataSource.httpData(from: FASubmissionsPage.url, cookies: cookies),
              let page = FASubmissionsPage(data: data)
        else { return [] }
        
        return page.submissions.compactMap { submission in
            guard let submission = submission else { return nil }
            return FASubmissionPreview(submission)
        }
    }
    
    open func submission(for preview: FASubmissionPreview) async -> FASubmission? {
        guard let data = await dataSource.httpData(from: preview.url, cookies: cookies),
              let page = FASubmissionPage(data: data)
        else { return nil }
        
        return FASubmission(page, url: preview.url)
    }
    
    open func notePreviews() async -> [FANotePreview] {
        guard let data = await dataSource.httpData(from: FANotesPage.url, cookies: cookies),
              let page = FANotesPage(data: data)
        else { return [] }
        
        return page.noteHeaders.compactMap { header in
            guard let header = header else { return nil }
            return FANotePreview(header)
        }
    }
    
    private let avatarUrlRequestsQueue = DispatchQueue(label: "FASession.AvatarRequests")
    private var cachedAvatarUrls = [String: URL]()
    private var avatarUrlTasks = [String: Task<URL?, Never>]()
    open func avatarUrl(for user: String) async -> URL? {
        let task = avatarUrlRequestsQueue.sync { () -> Task<URL?, Never> in
            let previousTask = avatarUrlTasks[user]
            let newTask = Task { () -> URL? in
                _ = await previousTask?.result
                if let url = cachedAvatarUrls[user] {
                    return url
                }
                
                guard let userpageUrl = FAUserPage.url(for: user),
                      let data = await dataSource.httpData(from: userpageUrl, cookies: cookies),
                      let page = FAUserPage(data: data),
                      let avatarUrl = page.avatarUrl
                else { return nil }
                
                cachedAvatarUrls[user] = avatarUrl
                return avatarUrl
            }
            
            avatarUrlTasks[user] = newTask
            return newTask
            
        }
        
        return try? await task.result.get()
    }
}

extension FASession {
    /// Initialize a FASession from the given session cookies.
    /// - Parameter cookies: The cookies for furaffinity.net after the user is logged
    /// in through a usual web browser.
    public convenience init?(cookies: [HTTPCookie], dataSource: HTTPDataSource = URLSession.shared) async {
        guard cookies.map(\.name).contains("a"),
              let data = await dataSource.httpData(from: FAHomePage.url, cookies: cookies),
              let page = FAHomePage(data: data)
        else { return nil }
        
        guard let username = page.username,
              let displayUsername = page.displayUsername
        else { return nil }
        
        self.init(username: username,
                  displayUsername: displayUsername,
                  cookies: cookies,
                  dataSource: dataSource)
    }
}

