//
//  FAUserGalleryLike.swift
//  
//
//  Created by Ceylo on 06/09/2023.
//

import Foundation
import FAPages

/// The representation for a gallery-like page (gallery, scraps, favorites)
public struct FAUserGalleryLike: Sendable, Equatable {
    public typealias FolderGroup = FAFolderGroup
    public typealias Folder = FAFolder
    
    public let url: URL
    public let displayAuthor: String
    public let previews: [FASubmissionPreview]
    public let nextPageUrl: URL?
    public let folderGroups: [FolderGroup]
    
    public init(
        url: URL,
        displayAuthor: String,
        previews: [FASubmissionPreview],
        nextPageUrl: URL?,
        folderGroups: [FolderGroup]
    ) {
        self.url = url
        self.displayAuthor = displayAuthor
        self.previews = previews
        self.nextPageUrl = nextPageUrl
        self.folderGroups = folderGroups
    }
    
    public func appending(_ gallery: Self) -> Self {
        .init(
            url: url,
            displayAuthor: displayAuthor,
            previews: previews + gallery.previews,
            nextPageUrl: gallery.nextPageUrl,
            folderGroups: folderGroups
        )
    }
}

extension FAUserGalleryLike {
    public init(_ page: FAUserGalleryLikePage, url: URL) {
        self.init(
            url: url,
            displayAuthor: page.displayAuthor,
            previews: page.previews
                .compactMap { $0 }
                .map { FASubmissionPreview($0) },
            nextPageUrl: page.nextPageUrl,
            folderGroups: page.folderGroups
        )
    }
}

