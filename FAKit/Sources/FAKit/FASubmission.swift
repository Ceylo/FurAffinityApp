//
//  FASubmission.swift
//  
//
//  Created by Ceylo on 21/11/2021.
//

import Foundation
import FAPages

public struct FASubmission: Equatable {
    public let url: URL
    public let previewImageUrl: URL
    public let fullResolutionImageUrl: URL
    public let widthOnHeightRatio: Float
    public let author: String
    public let displayAuthor: String
    public let authorAvatarUrl: URL
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let description: AttributedString
    public let isFavorite: Bool
    public let favoriteUrl: URL
    public let comments: [FAComment]
    
    public init(url: URL, previewImageUrl: URL,
                fullResolutionImageUrl: URL,
                widthOnHeightRatio: Float, author: String,
                displayAuthor: String, authorAvatarUrl: URL,
                title: String,
                datetime: String,
                naturalDatetime: String,
                description: AttributedString,
                isFavorite: Bool, favoriteUrl: URL,
                comments: [FAComment]) {
        self.url = url
        self.previewImageUrl = previewImageUrl
        self.fullResolutionImageUrl = fullResolutionImageUrl
        self.widthOnHeightRatio = widthOnHeightRatio
        self.author = author
        self.displayAuthor = displayAuthor
        self.authorAvatarUrl = authorAvatarUrl
        self.title = title
        self.datetime = datetime
        self.naturalDatetime = naturalDatetime
        self.description = description
        self.isFavorite = isFavorite
        self.favoriteUrl = favoriteUrl
        self.comments = comments
    }
}

extension FASubmission {
    public init(_ page: FASubmissionPage, url: URL) throws {
        try self.init(
            url: url,
            previewImageUrl: page.previewImageUrl,
            fullResolutionImageUrl: page.fullResolutionImageUrl,
            widthOnHeightRatio: page.widthOnHeightRatio,
            author: page.author,
            displayAuthor: page.displayAuthor,
            authorAvatarUrl: page.authorAvatarUrl,
            title: page.title,
            datetime: page.datetime,
            naturalDatetime: page.naturalDatetime,
            description: AttributedString(FAHTML: page.htmlDescription.selfContainedFAHtmlSubmission),
            isFavorite: page.isFavorite,
            favoriteUrl: page.favoriteUrl,
            comments: FAComment.buildCommentsTree(page.comments)
        )
    }
}
