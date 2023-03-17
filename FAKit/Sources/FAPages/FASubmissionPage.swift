//
//  FASubmissionsPage.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import Foundation
import SwiftSoup

public struct FASubmissionPage: Equatable {
    public let previewImageUrl: URL
    public let fullResolutionImageUrl: URL
    public let widthOnHeightRatio: Float
    public let author: String
    public let displayAuthor: String
    public let authorAvatarUrl: URL
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let htmlDescription: String
    public let isFavorite: Bool
    public let favoriteUrl: URL
    public let comments: [Comment]
    
    public struct Comment: Equatable {
        public let cid: Int
        public let indentation: Int
        public let author: String
        public let displayAuthor: String
        public let authorAvatarUrl: URL
        public let datetime: String
        public let htmlMessage: String
    }
}

extension FASubmissionPage {
    public init?(data: Data) {
        do {
            let state = signposter.beginInterval("Submission Parsing")
            defer { signposter.endInterval("Submission Parsing", state) }
            
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            let columnPageQuery = "body div#main-window div#site-content div#submission_page div#columnpage"
            let columnPageNode = try doc.select(columnPageQuery)
            let submissionInfoNodes = try columnPageNode.select("div.submission-sidebar section.info div")
            let sizeRowNode = try submissionInfoNodes.first(where: { try $0.text().starts(with: "Size") }).unwrap()
            let sizeText = try sizeRowNode.select("span").text()
            let groups = try #/(\d+) x (\d+)/#.wholeMatch(in: sizeText).unwrap()
            self.widthOnHeightRatio = try Float(groups.1).unwrap() / Float(groups.2).unwrap()
            
            let submissionContentNode = try columnPageNode.select("div.submission-content")
            let submissionImgNode = try submissionContentNode.select("div.submission-area img#submissionImg")
            
            let previewStr = try submissionImgNode.attr("data-preview-src")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                .unwrap()
            let fullViewStr = try submissionImgNode.attr("data-fullview-src")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                .unwrap()
            let previewUrl = try URL(string: "https:" + previewStr).unwrap()
            let fullViewUrl = try URL(string: "https:" + fullViewStr).unwrap()
            
            self.previewImageUrl = previewUrl
            self.fullResolutionImageUrl = fullViewUrl
            
            let favoriteNode = try submissionContentNode.select("div.favorite-nav a.button")
            let favoriteUrlNode = try favoriteNode
                .first(where: { ["+Fav", "-Fav"].contains(try $0.text()) })
                .unwrap()
            
            let favoriteUrlStr = try favoriteUrlNode.attr("href")
            let favoriteStatusStr = try favoriteUrlNode.text()
            self.favoriteUrl = try URL(string: "https://www.furaffinity.net" + favoriteUrlStr).unwrap()
            self.isFavorite = favoriteStatusStr == "-Fav"
            
            let avatarQuery = "section div.section-header div.submission-id-container div.submission-id-avatar img.avatar"
            let avatarNode = try submissionContentNode.select(avatarQuery)
            let avatarStr = try avatarNode.attr("src")
            let avatarUrl = try URL(string: "https:" + avatarStr).unwrap()
            
            self.authorAvatarUrl = avatarUrl
            
            let submissionContainerQuery = "section div.section-header div.submission-id-container div.submission-id-sub-container"
            let submissionContainerNode = try submissionContentNode.select(submissionContainerQuery)
            let titleNode = try submissionContainerNode.select("div.submission-title h2 p")
            self.title = try titleNode.text()
            
            let dateNode = try submissionContainerNode.select("strong span.popup_date")
            self.datetime = try dateNode.attr("title")
            self.naturalDatetime = try dateNode.text()
            
            let authorNode = try submissionContainerNode.select("a").first().unwrap()
            let authorUrl = try authorNode.attr("href")
            self.author = try authorUrl.substring(matching: "/user/(.+)/").unwrap()
            self.displayAuthor = try authorNode.text()
            
            let descriptionQuery = "section div.section-body div.submission-description"
            let descriptionNode = try submissionContentNode.select(descriptionQuery)
            let htmlContent = try descriptionNode.html()
            self.htmlDescription = htmlContent
            
            let commentNodes = try submissionContentNode.select("div.comments-list div#comments-submission div.comment_container")
            self.comments = try commentNodes.compactMap { try Comment($0) }
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}

extension FASubmissionPage.Comment {
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
        let authorAvatarUrl = try URL(string: "https:" + authorAvatarUrlString).unwrap()
        let displayAuthorQuery = "comment-container div.comment-content comment-username a.inline strong.comment_username"
        let displayAuthor = try node.select(displayAuthorQuery).text()
        let rawCidString = try node.select("a").attr("id")
        let cid = try Int(rawCidString.substring(matching: "cid:(.+)").unwrap()).unwrap()
        let datetime = try node.select("comment-container div.comment-content comment-date span.popup_date").text()
        let htmlMessage = try node.select("comment-container div.comment-content comment-user-text div.user-submitted-links").first().unwrap().html()
        
        self.init(cid: cid, indentation: indentation,
                  author: author, displayAuthor: displayAuthor,
                  authorAvatarUrl: authorAvatarUrl, datetime: datetime,
                  htmlMessage: htmlMessage)
    }
}
