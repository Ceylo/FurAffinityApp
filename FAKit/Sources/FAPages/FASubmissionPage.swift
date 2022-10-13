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
        let state = signposter.beginInterval("Submission Parsing")
        defer { signposter.endInterval("Submission Parsing", state) }
        
        guard let doc = try? SwiftSoup.parse(String(decoding: data, as: UTF8.self))
        else { return nil }
        
        let submissionContentQuery = "body div#main-window div#site-content div#submission_page div#columnpage div.submission-content"
        let imageQuery = submissionContentQuery + " div.submission-area img#submissionImg"
        guard let submissionImgNode = try? doc.select(imageQuery),
              let previewStr = try? submissionImgNode.attr("data-preview-src")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let fullViewStr = try? submissionImgNode.attr("data-fullview-src")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let previewUrl = URL(string: "https:" + previewStr),
              let fullViewUrl = URL(string: "https:" + fullViewStr)
        else { return nil }
        
        self.previewImageUrl = previewUrl
        self.fullResolutionImageUrl = fullViewUrl
        
        let favoriteQuery = submissionContentQuery + " div.favorite-nav a.button"
        guard let favoriteNode = try? doc.select(favoriteQuery),
              let favoriteUrlNode = try? favoriteNode.first(where: { ["+Fav", "-Fav"].contains(try $0.text()) }),
              let favoriteUrlStr = try? favoriteUrlNode.attr("href"),
              let favoriteStatusStr = try? favoriteUrlNode.text(),
              let favoriteUrl = URL(string: "https://www.furaffinity.net" + favoriteUrlStr)
        else { return nil }
        
        self.favoriteUrl = favoriteUrl
        self.isFavorite = favoriteStatusStr == "-Fav"
        
        let avatarQuery = submissionContentQuery + " section div.section-header div.submission-id-container div.submission-id-avatar img.avatar"
        guard let avatarNode = try? doc.select(avatarQuery),
              let avatarStr = try? avatarNode.attr("src"),
              let avatarUrl = URL(string: "https:" + avatarStr)
        else { return nil }
        
        self.authorAvatarUrl = avatarUrl
        
        let submissionContainerQuery = submissionContentQuery + " section div.section-header div.submission-id-container div.submission-id-sub-container"
        let submissionTitleQuery = submissionContainerQuery + " div.submission-title h2 p"
        guard let titleNode = try? doc.select(submissionTitleQuery),
              let title = try? titleNode.text()
        else { return nil }
        
        self.title = title
        
        let authorQuery = submissionContainerQuery + " a"
        guard let authorNode = try? doc.select(authorQuery),
              !authorNode.isEmpty(),
              let authorUrl = try? authorNode[0].attr("href"),
              let authorName = authorUrl.substring(matching: "/user/(.+)/"),
              let displayAuthorStr = try? authorNode[0].text()
        else { return nil }
        
        self.author = authorName
        self.displayAuthor = displayAuthorStr
        
        let descriptionQuery = submissionContentQuery + " section div.section-body div.submission-description"
        guard let descriptionNode = try? doc.select(descriptionQuery),
              let htmlContent = try? descriptionNode.html()
        else { return nil }
        self.htmlDescription = htmlContent
    }
}
