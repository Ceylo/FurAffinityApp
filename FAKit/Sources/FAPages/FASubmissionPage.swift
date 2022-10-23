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
    public let author: String
    public let displayAuthor: String
    public let authorAvatarUrl: URL
    public let title: String
    public let htmlDescription: String
    public let isFavorite: Bool
    public let favoriteUrl: URL
    public let comments: [Comment]
    
    public struct Comment: Equatable {
        public let cid: Int
        public let parentCid: Int?
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
            let submissionContentQuery = "body div#main-window div#site-content div#submission_page div#columnpage div.submission-content"
            let submissionContentNode = try doc.select(submissionContentQuery)
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
            
            let authorNode = try submissionContainerNode.select("a").first().unwrap()
            let authorUrl = try authorNode.attr("href")
            self.author = try authorUrl.substring(matching: "/user/(.+)/").unwrap()
            self.displayAuthor = try authorNode.text()
            
            let descriptionQuery = "section div.section-body div.submission-description"
            let descriptionNode = try submissionContentNode.select(descriptionQuery)
            let htmlContent = try descriptionNode.html()
            self.htmlDescription = htmlContent
            
            let commentNodes = try submissionContentNode.select("div.comments-list div#comments-submission div.comment_container")
            self.comments = try commentNodes.map { try Comment($0) }
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}

extension FASubmissionPage.Comment {
    init(_ node: SwiftSoup.Element) throws {
        let tableNode = try node.select("div.base div.header div.name div.table")
        let authorUrlString = try tableNode.select("div.avatar-mobile a").attr("href")
        let author = try authorUrlString.substring(matching: "/user/(.+)/").unwrap()
        let authorAvatarUrlString = try tableNode.select("div.avatar-mobile a img.comment_useravatar").attr("src")
        let authorAvatarUrl = try URL(string: "https:" + authorAvatarUrlString).unwrap()
        let displayAuthor = try tableNode.select("div.cell a.inline strong.comment_username h3").text()
        let floatRightNode = try tableNode.select("div.cell div.floatright")
        let rawCidString = try floatRightNode.select("a.comment-link").attr("href")
        let cid = try Int(rawCidString.substring(matching: "#cid:(.+)").unwrap()).unwrap()
        let rawParentCidString = try? floatRightNode.select("a.comment-parent").first().unwrap().attr("href")
        let parentCid = try rawParentCidString.flatMap { Int(try $0.substring(matching: "#cid:(.+)").unwrap()) }
        let datetime = try tableNode.select("div.cell div.comment-date span.popup_date").text()
        let htmlMessage = try node.select("div.base div.comment_text").first().unwrap().html()
        
        self.init(cid: cid, parentCid: parentCid,
                  author: author, displayAuthor: displayAuthor,
                  authorAvatarUrl: authorAvatarUrl, datetime: datetime,
                  htmlMessage: htmlMessage)
    }
}
