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
    private let cookies: [HTTPCookie]
    private let dataSource: HTTPDataSource
    
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
    
    private var cachedAvatarUrls = [String: URL]()
    private let avatarUrlRequestsQueue = DispatchQueue(label: "FASession.AvatarRequests", qos: .default)
    open func avatarUrl(for user: String) async -> URL? {
        await withCheckedContinuation { continuation in
            avatarUrlRequestsQueue.async { [self] in
                if let url = cachedAvatarUrls[user] {
                    continuation.resume(returning: url)
                    return
                }
                
                guard let userpageUrl = FAUserPage.url(for: user) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let sema = DispatchSemaphore(value: 0)
                dataSource.httpData(from: userpageUrl, cookies: cookies) { data in
                    guard let data = data,
                          let page = FAUserPage(data: data),
                          let avatarUrl = page.avatarUrl
                    else {
                        continuation.resume(returning: nil)
                        sema.signal()
                        return
                    }
                    
                    cachedAvatarUrls[user] = avatarUrl
                    continuation.resume(returning: avatarUrl)
                    sema.signal()
                }
                sema.wait()
            }
        }
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

