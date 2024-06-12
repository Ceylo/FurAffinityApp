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
    public let favoriteCount: Int
    public let favoriteUrl: URL
    public let comments: [FAPageComment]
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
            let fullViewStr = try submissionImgNode.attr("data-fullview-src")
            let previewUrl = try URL(unsafeString: "https:" + previewStr)
            let fullViewUrl = try URL(unsafeString: "https:" + fullViewStr)
            
            self.previewImageUrl = previewUrl
            self.fullResolutionImageUrl = fullViewUrl
            
            let favoriteNode = try submissionContentNode.select("div.favorite-nav a.button")
            let favoriteUrlNode = try favoriteNode
                .first(where: { ["+Fav", "-Fav"].contains(try $0.text()) })
                .unwrap()
            
            let favoriteUrlStr = try favoriteUrlNode.attr("href")
            let favoriteStatusStr = try favoriteUrlNode.text()
            self.favoriteUrl = try URL(unsafeString: FAURLs.homeUrl.absoluteString + favoriteUrlStr)
            self.isFavorite = favoriteStatusStr == "-Fav"
            let favCountQuery = "div.submission-sidebar section.stats-container.text div.favorites span.font-large"
            let favCountNode = try columnPageNode.select(favCountQuery)
            let favCount = try Int(favCountNode.text()).unwrap()
            self.favoriteCount = favCount
            
            let avatarQuery = "section div.section-header div.submission-id-container div.submission-id-avatar img.avatar"
            let avatarNode = try submissionContentNode.select(avatarQuery)
            let avatarStr = try avatarNode.attr("src")
            let avatarUrl = try URL(unsafeString: "https:" + avatarStr)
            
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
            self.comments = try commentNodes.compactMap { try FAPageComment($0, type: .comment) }
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}
