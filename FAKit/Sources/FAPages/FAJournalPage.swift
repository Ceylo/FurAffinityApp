//
//  FAJournalPage.swift
//  
//
//  Created by Ceylo on 16/04/2023.
//

import Foundation
import SwiftSoup

public struct FAJournalPage: Equatable {
    public let author: String
    public let displayAuthor: String
    public let authorAvatarUrl: URL
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let htmlDescription: String
    public let comments: [FAPageComment]
}

extension FAJournalPage {
    public init?(data: Data) {
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
            let avatarSrc = try avatarNode.select("img").attr("src")
            self.authorAvatarUrl = try URL(unsafeString: "https:" + avatarSrc)
            
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
                "div.journal-body-theme div.journal-item div.journal-content-container div.journal-content"
            ).html()
            
            let commentNodes = try siteContentNode.select(
                "div#columnpage div.content div#comments-journal div.comment_container"
            )
            self.comments = try commentNodes.compactMap { try FAPageComment($0) }
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}
