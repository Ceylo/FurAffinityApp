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
    
    public let displayAuthor: String
    public let previews: [FASubmissionPreview]
    public let nextPageUrl: URL?
    public let folderGroups: [FolderGroup]
    
    public init(
        displayAuthor: String,
        previews: [FASubmissionPreview],
        nextPageUrl: URL?,
        folderGroups: [FolderGroup]
    ) {
        self.displayAuthor = displayAuthor
        self.previews = previews
        self.nextPageUrl = nextPageUrl
        self.folderGroups = folderGroups
    }
    
    public func appending(_ gallery: Self) -> Self {
        .init(
            displayAuthor: displayAuthor,
            previews: previews + gallery.previews,
            nextPageUrl: gallery.nextPageUrl,
            folderGroups: folderGroups
        )
    }
}

extension FAUserGalleryLike {
    public init(_ page: FAUserGalleryLikePage) {
        self.init(
            displayAuthor: page.displayAuthor,
            previews: page.previews
                .compactMap { $0 }
                .map { FASubmissionPreview($0) },
            nextPageUrl: page.nextPageUrl,
            folderGroups: page.folderGroups
        )
    }
}

