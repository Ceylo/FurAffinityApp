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
}

extension FASubmissionPage {
    public init?(data: Data) {
        do {
            let state = signposter.beginInterval("Submission Parsing")
            defer { signposter.endInterval("Submission Parsing", state) }
            
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            let submissionContentQuery = "body div#main-window div#site-content div#submission_page div#columnpage div.submission-content"
            let imageQuery = submissionContentQuery + " div.submission-area img#submissionImg"
            let submissionImgNode = try doc.select(imageQuery)
            
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
            
            let favoriteQuery = submissionContentQuery + " div.favorite-nav a.button"
            let favoriteNode = try doc.select(favoriteQuery)
            let favoriteUrlNode = try favoriteNode
                .first(where: { ["+Fav", "-Fav"].contains(try $0.text()) })
                .unwrap()
            
            let favoriteUrlStr = try favoriteUrlNode.attr("href")
            let favoriteStatusStr = try favoriteUrlNode.text()
            self.favoriteUrl = try URL(string: "https://www.furaffinity.net" + favoriteUrlStr).unwrap()
            self.isFavorite = favoriteStatusStr == "-Fav"
            
            let avatarQuery = submissionContentQuery + " section div.section-header div.submission-id-container div.submission-id-avatar img.avatar"
            let avatarNode = try doc.select(avatarQuery)
            let avatarStr = try avatarNode.attr("src")
            let avatarUrl = try URL(string: "https:" + avatarStr).unwrap()
            
            self.authorAvatarUrl = avatarUrl
            
            let submissionContainerQuery = submissionContentQuery + " section div.section-header div.submission-id-container div.submission-id-sub-container"
            let submissionTitleQuery = submissionContainerQuery + " div.submission-title h2 p"
            let titleNode = try doc.select(submissionTitleQuery)
            self.title = try titleNode.text()
            
            let authorQuery = submissionContainerQuery + " a"
            let authorNode = try doc.select(authorQuery).first().unwrap()
            let authorUrl = try authorNode.attr("href")
            self.author = try authorUrl.substring(matching: "/user/(.+)/").unwrap()
            self.displayAuthor = try authorNode.text()
            
            let descriptionQuery = submissionContentQuery + " section div.section-body div.submission-description"
            let descriptionNode = try doc.select(descriptionQuery)
            let htmlContent = try descriptionNode.html()
            self.htmlDescription = htmlContent
        } catch {
            logger.error("\(#file) - \(error)")
            return nil
        }
    }
}
