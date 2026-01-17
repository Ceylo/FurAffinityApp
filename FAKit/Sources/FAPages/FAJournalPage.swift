//
//  FAJournalPage.swift
//  
//
//  Created by Ceylo on 16/04/2023.
//

import Foundation
import SwiftSoup

public struct FAJournalPage: FAPage {
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
    public init(data: Data, url: URL) throws {
        let state = signposter.beginInterval("Journal Parsing")
        defer { signposter.endInterval("Journal Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            let siteContentNode = try doc.select(
                "html body#pageid-journal div#main-window div#site-content"
            )
            
            let userNode = try siteContentNode.select(
                "userpage-nav-header userpage-nav-user-details username div.c-usernameBlock a.c-usernameBlock__displayName"
            )
            self.author = try userNode.attr("href")
                .substring(matching: "/user/(.+)/")
                .unwrap()
            self.displayAuthor = try String(userNode.text())
            
            let sectionNode = try siteContentNode.select(
                "div#columnpage div.content section"
            )
            self.title = try sectionNode
                .select("div.section-header div#c-journalTitleTop span#c-journalTitleTop__subject")
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
            self.comments = try commentNodes
                .map { try FAPageComment($0, type: .comment) }
                .compactMap { $0 }
            
            self.targetCommentId = url.absoluteString
                .substring(matching: #"www\.furaffinity\.net\/journal\/\d+\/#cid:(\d+)$"#)
                .flatMap { Int($0) }
            
            let commentsDisabledNode = try siteContentNode.select("div#columnpage div#responsebox")
            let commentsDisabled = try commentsDisabledNode.text().contains("Comment posting has been disabled")
            self.acceptsNewComments = !commentsDisabled
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            throw error
        }
    }
}
