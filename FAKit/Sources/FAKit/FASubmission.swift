//
//  FASubmission.swift
//  
//
//  Created by Ceylo on 21/11/2021.
//

import Foundation
import FAPages

public typealias Rating = FAPages.Rating

public struct FASubmission: Equatable, Sendable {
    public typealias Metadata = FASubmissionPage.Metadata
    
    public let url: URL
    public let previewImageUrl: URL
    public let fullResolutionMediaUrl: URL
    public let widthOnHeightRatio: Float
    public let metadata: Metadata
    public var author: String { metadata.author }
    public var displayAuthor: String { metadata.displayAuthor }
    public var title: String { metadata.title }
    public var datetime: String { metadata.datetime }
    public var naturalDatetime: String { metadata.naturalDatetime }
    public let description: AttributedString
    public let isFavorite: Bool
    public var favoriteCount: Int {metadata.favoriteCount }
    public let favoriteUrl: URL
    public let comments: [FAComment]
    public let targetCommentId: Int?
    public let acceptsNewComments: Bool
    
    public init(
        url: URL, previewImageUrl: URL,
        fullResolutionMediaUrl: URL,
        widthOnHeightRatio: Float,
        metadata: Metadata,
        description: AttributedString,
        isFavorite: Bool,
        favoriteUrl: URL,
        comments: [FAComment],
        targetCommentId: Int?,
        acceptsNewComments: Bool
    ) {
        self.url = url
        self.previewImageUrl = previewImageUrl
        self.fullResolutionMediaUrl = fullResolutionMediaUrl
        self.widthOnHeightRatio = widthOnHeightRatio
        self.metadata = metadata
        self.description = description
        self.isFavorite = isFavorite
        self.favoriteUrl = favoriteUrl
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
            metadata: metadata.togglingFavorite(isFavorite),
            description: description,
            isFavorite: !isFavorite,
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
            metadata: page.metadata,
            description: await AttributedString(FAHTML: page.htmlDescription.selfContainedFAHtmlSubmission),
            isFavorite: page.isFavorite,
            favoriteUrl: page.favoriteUrl,
            comments: await FAComment.buildCommentsTree(page.comments),
            targetCommentId: page.targetCommentId,
            acceptsNewComments: page.acceptsNewComments
        )
    }
}
