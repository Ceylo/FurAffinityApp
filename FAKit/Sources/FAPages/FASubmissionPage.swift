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

public struct FASubmissionPage: Equatable, Sendable {
    public struct Metadata: Hashable, Sendable {
        public init(title: String, author: String, displayAuthor: String, datetime: String, naturalDatetime: String, viewCount: Int, commentCount: Int, favoriteCount: Int, rating: Rating, category: String, species: String, size: String, fileSize: String, keywords: [String], folders: [FAFolder]) {
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
            self.species = species
            self.size = size
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
        public let species: String
        public let size: String
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
    public init?(data: Data, url: URL) {
        do {
            let state = signposter.beginInterval("Submission Parsing")
            defer { signposter.endInterval("Submission Parsing", state) }
            
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            let columnPageQuery = "body div#main-window div#site-content div#submission_page div#columnpage"
            let columnPageNode = try doc.select(columnPageQuery)
            let sidebarNode = try columnPageNode.select("div.submission-sidebar")
            let submissionInfoNodes = try sidebarNode.select("section.info div")
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
            self.fullResolutionMediaUrl = fullViewUrl
            
            let favoriteNode = try submissionContentNode.select("div.favorite-nav a.button")
            let favoriteUrlNode = try favoriteNode
                .first(where: { ["+Fav", "-Fav"].contains(try $0.text()) })
                .unwrap()
            
            let favoriteUrlStr = try favoriteUrlNode.attr("href")
            let favoriteStatusStr = try favoriteUrlNode.text()
            self.favoriteUrl = try URL(unsafeString: FAURLs.homeUrl.absoluteString + favoriteUrlStr)
            self.isFavorite = favoriteStatusStr == "-Fav"
                        
            let submissionContainerQuery = "section div.section-header div.submission-id-container div.submission-id-sub-container"
            let submissionContainerNode = try submissionContentNode.select(submissionContainerQuery)
            let titleNode = try submissionContainerNode.select("div.submission-title h2 p")
            let title = try titleNode.text()
            
            let dateNode = try submissionContainerNode.select("strong span.popup_date")
            let datetime = try dateNode.attr("title")
            let naturalDatetime = try dateNode.text()
            
            let authorNode = try submissionContainerNode.select("a").first().unwrap()
            let authorUrl = try authorNode.attr("href")
            let author = try authorUrl.substring(matching: "/user/(.+)/").unwrap()
            let displayAuthor = try authorNode.text()
            
            let descriptionQuery = "section div.section-body div.submission-description"
            let descriptionNode = try submissionContentNode.select(descriptionQuery)
            let htmlContent = try descriptionNode.html()
            self.htmlDescription = htmlContent
            
            let commentNodes = try submissionContentNode.select("div.comments-list div#comments-submission div.comment_container")
            self.comments = try commentNodes
                .map { try FAPageComment($0, type: .comment) }
                .compactMap { $0 }
            
            self.targetCommentId = url.absoluteString
                .substring(matching: #"www\.furaffinity\.net\/view\/\d+\/#cid:(\d+)$"#)
                .flatMap { Int($0) }
            
            let commentsDisabledNode = try columnPageNode.select("div#responsebox")
            let commentsDisabled = try commentsDisabledNode.text().contains("Comment posting has been disabled")
            self.acceptsNewComments = !commentsDisabled
            
            let statsNode = try sidebarNode.select("section.stats-container")
            let viewCountNode = try statsNode.select("div.views > span.font-large")
            let viewCount = try Int(viewCountNode.text()).unwrap()
            let commentCountNode = try statsNode.select("div.comments > span.font-large")
            let commentCount = try Int(commentCountNode.text()).unwrap()
            let favoriteCountNode = try statsNode.select("div.favorites > span.font-large")
            let favoriteCount = try Int(favoriteCountNode.text()).unwrap()
            let ratingNode = try statsNode.select("div.rating > span.rating-box")
            let ratingStr = try ratingNode.text().trimmingCharacters(in: .whitespaces)
            let rating = try Rating(ratingStr).unwrap()
            
            let readRow = { (name: String, childContainer: String) in
                let node = try submissionInfoNodes.first(where: { try $0.text().starts(with: name) }).unwrap()
                return try node.select("div > \(childContainer)").text()
            }
            let category = try readRow("Category", "div")
            let species = try readRow("Species", "span")
            let fileSize = try readRow("File Size", "span")
            
            let keywordNodes = try sidebarNode.select("section.tags-row > span.tags")
            let keywords = try keywordNodes.compactMap { node in
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
            
            let folderNodes = try sidebarNode.select("section.folder-list-container > div > a")
            let folders = try folderNodes.map {
                let href = try $0.attr("href")
                let url = try URL(unsafeString: FAURLs.homeUrl.absoluteString + href)
                return try FAFolder(title: $0.text(), url: url, isActive: false)
            }
            
            self.metadata = .init(
                title: title,
                author: author,
                displayAuthor: displayAuthor,
                datetime: datetime,
                naturalDatetime: naturalDatetime,
                viewCount: viewCount,
                commentCount: commentCount,
                favoriteCount: favoriteCount,
                rating: rating,
                category: category,
                species: species,
                size: sizeText,
                fileSize: fileSize,
                keywords: keywords,
                folders: folders
            )
            
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}

extension FASubmissionPage.Metadata {
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
            species: species,
            size: size,
            fileSize: fileSize,
            keywords: keywords,
            folders: folders
        )
    }
}
