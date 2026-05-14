//
//  FASubmissionsPage.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import Foundation
import SwiftSoup

public enum Rating: Sendable {
    case general
    case mature
    case adult
}

extension Rating {
    init?(_ rawValue: String) {
        switch rawValue {
        case "General":
            self = .general
        case "Mature":
            self = .mature
        case "Adult":
            self = .adult
        default:
            return nil
        }
    }
}

public struct FASubmissionPage: FAPage {
    public struct Metadata: Hashable, Sendable {
        public init(title: String, author: String, displayAuthor: String, datetime: String, naturalDatetime: String, viewCount: Int, commentCount: Int, favoriteCount: Int, rating: Rating, category: String, theme: String, species: String, resolution: String, fileSize: String, keywords: [String], folders: [FAFolder]) {
            self.title = title
            self.author = author
            self.displayAuthor = displayAuthor
            self.datetime = datetime
            self.naturalDatetime = naturalDatetime
            self.viewCount = viewCount
            self.commentCount = commentCount
            self.favoriteCount = favoriteCount
            self.rating = rating
            self.category = category
            self.theme = theme
            self.species = species
            self.resolution = resolution
            self.fileSize = fileSize
            self.keywords = keywords
            self.folders = folders
        }
        
        public let title: String
        public let author: String
        public let displayAuthor: String
        public let datetime: String
        public let naturalDatetime: String
        
        public let viewCount: Int
        public let commentCount: Int
        public let favoriteCount: Int
        public let rating: Rating
        
        public let category: String
        public let theme: String
        public let species: String
        public let resolution: String
        public let fileSize: String
        public let keywords: [String]
        public let folders: [FAFolder]
    }
    
    public let previewImageUrl: URL
    public let fullResolutionMediaUrl: URL
    public let widthOnHeightRatio: Float
    public let metadata: Metadata
    public let htmlDescription: String
    public let isFavorite: Bool
    public let favoriteUrl: URL
    public let comments: [FAPageComment]
    public let targetCommentId: Int?
    public let acceptsNewComments: Bool
}

extension FASubmissionPage {
    public init(data: Data, url: URL) throws {
        do {
            let state = signposter.beginInterval("Submission Parsing")
            defer { signposter.endInterval("Submission Parsing", state) }
            
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            
            let submissionPageContentQuery = "body#pageid-submission div#main-window div#site-content div#submission_page div div.submission-page-content"
            let submissionPageContentNode = try doc
                .select(submissionPageContentQuery)
            let submissionMainContentNode = try submissionPageContentNode
                .select("div#submission-main-content")
            
            let submissionContentQuery = "div div.submission-content"
            let submissionContentNode = try submissionMainContentNode.select(submissionContentQuery)
            let submissionImgNode = try submissionContentNode.select("div.submission-area img#submissionImg")
            let previewStr = try submissionImgNode.attr("data-preview-src")
            let fullViewStr = try submissionImgNode.attr("data-fullview-src")
            let previewUrl = try URL(unsafeString: "https:" + previewStr)
            let fullViewUrl = try URL(unsafeString: "https:" + fullViewStr)
            
            self.previewImageUrl = previewUrl
            self.fullResolutionMediaUrl = fullViewUrl
            
            let favoriteNode = try submissionContentNode.select("div.submission-content-inner div#submission-options a.button")
            let favoriteUrlNode = try favoriteNode
                .first(where: { ["+Fav", "-Fav"].contains(try $0.text()) })
                .unwrap()
            
            let favoriteUrlStr = try favoriteUrlNode.attr("href")
            let favoriteStatusStr = try favoriteUrlNode.text()
            self.favoriteUrl = try URL(unsafeString: FAURLs.homeUrl.absoluteString + favoriteUrlStr)
            self.isFavorite = favoriteStatusStr == "-Fav"
            
            let descriptionQuery = "div div.submission-details div section.submission-description div.section-body div.submission-description-text"
            let descriptionNode = try submissionMainContentNode.select(descriptionQuery)
            let htmlContent = try descriptionNode.html()
            self.htmlDescription = htmlContent
            
            let commentNodes = try submissionPageContentNode.select("div.comments-list div#comments-submission div.comment_container")
            self.comments = try commentNodes
                .map { try FAPageComment($0, type: .comment) }
                .compactMap { $0 }
            
            self.targetCommentId = url.absoluteString
                .substring(matching: #"www\.furaffinity\.net\/view\/\d+\/#cid:(\d+)$"#)
                .flatMap { Int($0) }
            
            let commentsDisabledNode = try submissionPageContentNode
                .select("div.comments-list div#responsebox")
            let commentsDisabled = try commentsDisabledNode.text().contains("Comment posting has been disabled")
            self.acceptsNewComments = !commentsDisabled
            
            self.metadata = try .init(root: doc)
            
            let groups = try #/(\d+) x (\d+)/#.wholeMatch(in: self.metadata.resolution).unwrap()
            self.widthOnHeightRatio = try Float(groups.1).unwrap() / Float(groups.2).unwrap()
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            throw error
        }
    }
}

extension FASubmissionPage.Metadata {
    init(root: Element) throws {
        let submissionMainContentQuery = "body#pageid-submission div#main-window div#site-content div#submission_page div div.submission-page-content div#submission-main-content"
        let submissionMainContentNode = try root.select(submissionMainContentQuery)
        
        let submissionDescriptionHeaderQuery = "div div.submission-details div section.submission-description div.section-header.submission-description-header"
        let submissionDescriptionHeaderNode = try submissionMainContentNode
            .select(submissionDescriptionHeaderQuery)
        let submissionDescriptionArtistNode = try submissionDescriptionHeaderNode
            .select("div.submission-description-artist")
        
        let titleQuery = "div div.submission-title h2"
        let titleNode = try submissionDescriptionArtistNode.select(titleQuery)
        self.title = try titleNode.text()
        
        let authorQuery = "div div span span.c-usernameBlockSimple a"
        let authorNode = try submissionDescriptionArtistNode
            .select(authorQuery).first().unwrap()
        let authorUrl = try authorNode.attr("href")
        self.author = try authorUrl.substring(matching: "/user/(.+)/").unwrap()
        self.displayAuthor = try authorNode.text()
        
        let dateNode = try submissionDescriptionHeaderNode.select("div div span.popup_date")
        self.datetime = try dateNode.attr("title")
        self.naturalDatetime = try dateNode.text()
        
        let submissionPageStatsNode = try submissionMainContentNode
            .select("div div div.submission-page-stats")

        let viewCountNode = try submissionPageStatsNode
            .select(#"div[title="Views"] div"#).first().unwrap()
        self.viewCount = try Int(viewCountNode.text()).unwrap()

        let commentCountNode = try submissionPageStatsNode
            .select(#"div[title="Comments"] div"#).first().unwrap()
        self.commentCount = try Int(commentCountNode.text()).unwrap()

        let favoriteCountNode = try submissionPageStatsNode
            .select(#"div[title="Favorites"] div"#).first().unwrap()
        self.favoriteCount = try Int(favoriteCountNode.text()).unwrap()
        
        let contentRatingNode = try submissionPageStatsNode
            .select(#"div div[class*="c-contentRating"]"#)
        self.rating = try .init(contentRatingNode.text()).unwrap()

        let submissionContentStatsNode = try submissionMainContentNode
            .select("div div.submission-content-stats")
        let spans = try submissionContentStatsNode.select("> span")
        guard spans.count == 2 else {
            throw FAPagesError.parserFailureError()
        }
        let catories = try spans[0].select("> span").map { try $0.text() }
        let values = try spans[1].select("> span").map { try $0.text() }
        
        guard !catories.isEmpty, catories.count == values.count else {
            throw FAPagesError.parserFailureError()
        }
        let stats = Dictionary(uniqueKeysWithValues: zip(catories, values))
        self.category = try stats["Category"].unwrap()
        self.theme = try stats["Theme"].unwrap()
        self.species = try stats["Species"].unwrap()
        self.resolution = try stats["Resolution"].unwrap()
        self.fileSize = try stats["File Size"].unwrap()

        let keywordNodes = try submissionMainContentNode
            .select("div div.submission-tags div span.tags")
        self.keywords = try keywordNodes.compactMap { node in
            if let tag = try node.getElementsByClass("tag-block").first() {
                return try tag.attr("data-tag-name")
            } else if let tag = try node.getElementsByClass("tag-invalid").first() {
                return try tag.text()
            } else {
                let html = (try? node.html()) ?? "exception throw while retrieving html"
                logger.error("Failed parsing keyword. Node: \(html)")
                return nil
            }
        }
        
        let foldersQuery = "div div#submission-sidebar-footer div.submission-controls-lower div.folder-list-container div div.submission-folder a"
        let foldersNodes = try submissionMainContentNode.select(foldersQuery)
        self.folders = try foldersNodes.map {
            let href = try $0.attr("href")
            let url = try URL(unsafeString: FAURLs.homeUrl.absoluteString + href)
            return try FAFolder(title: $0.text(), url: url, isActive: false)
        }
    }
    
    public func togglingFavorite(_ newIsFavorite: Bool) -> Self {
        Self.init(
            title: title,
            author: author,
            displayAuthor: displayAuthor,
            datetime: datetime,
            naturalDatetime: naturalDatetime,
            viewCount: viewCount,
            commentCount: commentCount,
            favoriteCount: self.favoriteCount + (newIsFavorite ? -1 : 1),
            rating: rating,
            category: category,
            theme: theme,
            species: species,
            resolution: resolution,
            fileSize: fileSize,
            keywords: keywords,
            folders: folders
        )
    }
}
