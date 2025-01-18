//
//  FAJournalPage.swift
//  
//
//  Created by Ceylo on 16/04/2023.
//

import Foundation
@preconcurrency import SwiftSoup

public struct FAJournalPage: Equatable, Sendable {
    public let author: String
    public let displayAuthor: String
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let htmlDescription: String
    public let comments: [FAPageComment]
    public let targetCommentId: Int?
    public let acceptsNewComments: Bool
}

extension FAJournalPage {
    public init?(data: Data, url: URL) async {
        let state = signposter.beginInterval("Journal Parsing")
        defer { signposter.endInterval("Journal Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            let siteContentNode = try doc.select(
                "html body#pageid-journal div#main-window div#site-content"
            )
            let avatarNode = try siteContentNode.select(
                "userpage-nav-header userpage-nav-avatar a.current"
            )
            
            self.author = try avatarNode.attr("href")
                .substring(matching: "/user/(.+)/")
                .unwrap()
            
            let userNode = try siteContentNode.select(
                "userpage-nav-header userpage-nav-user-details h1 username"
            )
            self.displayAuthor = try String(userNode.text().dropFirst())
            
            let sectionNode = try siteContentNode.select(
                "div#columnpage div.content section"
            )
            self.title = try sectionNode
                .select("div.section-header h2.journal-title")
                .text()
            let datetimeNode = try sectionNode
                .select("div.section-header div span.popup_date")
            self.datetime = try datetimeNode.attr("title")
            self.naturalDatetime = try datetimeNode.text()
            
            self.htmlDescription = try sectionNode.select(
                "div.journal-body-theme div.journal-item"
            ).html()
            
            let commentNodes = try siteContentNode.select(
                "div#columnpage div.content div#comments-journal div.comment_container"
            )
            self.comments = try await commentNodes
                .parallelMap { try FAPageComment($0, type: .comment) }
                .compactMap { $0 }
            
            self.targetCommentId = url.absoluteString
                .substring(matching: #"www\.furaffinity\.net\/journal\/\d+\/#cid:(\d+)$"#)
                .flatMap { Int($0) }
            
            let commentsDisabledNode = try siteContentNode.select("div#columnpage div#responsebox")
            let commentsDisabled = try commentsDisabledNode.text().contains("Comment posting has been disabled")
            self.acceptsNewComments = !commentsDisabled
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}
