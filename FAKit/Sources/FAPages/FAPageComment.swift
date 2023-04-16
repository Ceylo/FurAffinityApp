//
//  FAPageComment.swift
//  
//
//  Created by Ceylo on 16/04/2023.
//

import Foundation
import SwiftSoup

public struct FAPageComment: Equatable {
    public let cid: Int
    public let indentation: Int
    public let author: String
    public let displayAuthor: String
    public let authorAvatarUrl: URL
    public let datetime: String
    public let naturalDatetime: String
    public let htmlMessage: String
}

extension FAPageComment {
    init?(_ node: SwiftSoup.Element) throws {
        let usernameNode = try node.select("comment-container div.comment-content comment-username")
        guard !usernameNode.isEmpty() else {
            let html = try? node.html()
            logger.warning("Skipping comment: \(html ?? "", privacy: .public)")
            return nil
        }
        
        let widthStr = try node.attr("style").substring(matching: "width:(.+)%").unwrap()
        let indentation = try 100 - Int(widthStr).unwrap()
        let authorNode = try node.select("comment-container div.avatar a")
        let author = try authorNode.attr("href").substring(matching: "/user/(.+)/").unwrap()
        let authorAvatarUrlString = try authorNode.select("img").attr("src")
        let authorAvatarUrl = try URL(unsafeString: "https:" + authorAvatarUrlString)
        let displayAuthorQuery = "comment-container div.comment-content comment-username a.inline strong.comment_username"
        let displayAuthor = try node.select(displayAuthorQuery).text()
        let rawCidString = try node.select("a").attr("id")
        let cid = try Int(rawCidString.substring(matching: "cid:(.+)").unwrap()).unwrap()
        let datetimeNode = try node.select("comment-container div.comment-content comment-date span.popup_date")
        let naturalDatetime = try datetimeNode.text()
        let datetime = try datetimeNode.attr("title")
        let htmlMessage = try node.select("comment-container div.comment-content comment-user-text div.user-submitted-links").first().unwrap().html()
        
        self.init(cid: cid, indentation: indentation,
                  author: author, displayAuthor: displayAuthor,
                  authorAvatarUrl: authorAvatarUrl, datetime: datetime,
                  naturalDatetime: naturalDatetime, htmlMessage: htmlMessage)
    }
}
