//
//  FASubmission.swift
//  
//
//  Created by Ceylo on 21/11/2021.
//

import Foundation
import FAPages

public struct FASubmission: Equatable, Sendable {
    public let url: URL
    public let previewImageUrl: URL
    public let fullResolutionMediaUrl: URL
    public let widthOnHeightRatio: Float
    public let author: String
    public let displayAuthor: String
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let description: AttributedString
    public let isFavorite: Bool
    public let favoriteCount: Int
    public let favoriteUrl: URL
    public let comments: [FAComment]
    public let targetCommentId: Int?
    public let acceptsNewComments: Bool
    
    public init(
        url: URL, previewImageUrl: URL,
        fullResolutionMediaUrl: URL,
        widthOnHeightRatio: Float, author: String,
        displayAuthor: String,
        title: String,
        datetime: String,
        naturalDatetime: String,
        description: AttributedString,
        isFavorite: Bool,
        favoriteCount: Int,
        favoriteUrl: URL,
        comments: [FAComment],
        targetCommentId: Int?,
        acceptsNewComments: Bool
    ) {
        self.url = url
        self.previewImageUrl = previewImageUrl
        self.fullResolutionMediaUrl = fullResolutionMediaUrl
        self.widthOnHeightRatio = widthOnHeightRatio
        self.author = author
        self.displayAuthor = displayAuthor
        self.title = title
        self.datetime = datetime
        self.naturalDatetime = naturalDatetime
        self.description = description
        self.isFavorite = isFavorite
        self.favoriteUrl = favoriteUrl
        self.favoriteCount = favoriteCount
        self.comments = comments
        self.targetCommentId = targetCommentId
        self.acceptsNewComments = acceptsNewComments
    }
    
    public func togglingFavorite() -> FASubmission {
        .init(
            url: url,
            previewImageUrl: previewImageUrl,
            fullResolutionMediaUrl: fullResolutionMediaUrl,
            widthOnHeightRatio: widthOnHeightRatio,
            author: author,
            displayAuthor: displayAuthor,
            title: title,
            datetime: datetime,
            naturalDatetime: naturalDatetime,
            description: description,
            isFavorite: !isFavorite,
            favoriteCount: favoriteCount + (isFavorite ? -1 : 1),
            favoriteUrl: favoriteUrl,
            comments: comments,
            targetCommentId: targetCommentId,
            acceptsNewComments: acceptsNewComments
        )
    }
}

extension FASubmission {
    public init(_ page: FASubmissionPage, url: URL) async throws {
        try self.init(
            url: url,
            previewImageUrl: page.previewImageUrl,
            fullResolutionMediaUrl: page.fullResolutionMediaUrl,
            widthOnHeightRatio: page.widthOnHeightRatio,
            author: page.author,
            displayAuthor: page.displayAuthor,
            title: page.title,
            datetime: page.datetime,
            naturalDatetime: page.naturalDatetime,
            description: await AttributedString(FAHTML: page.htmlDescription.selfContainedFAHtmlSubmission),
            isFavorite: page.isFavorite,
            favoriteCount: page.favoriteCount,
            favoriteUrl: page.favoriteUrl,
            comments: await FAComment.buildCommentsTree(page.comments),
            targetCommentId: page.targetCommentId,
            acceptsNewComments: page.acceptsNewComments
        )
    }
}
