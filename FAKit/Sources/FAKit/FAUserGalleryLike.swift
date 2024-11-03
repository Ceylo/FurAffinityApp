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
    public let displayAuthor: String
    public let previews: [FASubmissionPreview]
    public let nextPageUrl: URL?
    
    public init(
        displayAuthor: String,
        previews: [FASubmissionPreview],
        nextPageUrl: URL?
    ) {
        self.displayAuthor = displayAuthor
        self.previews = previews
        self.nextPageUrl = nextPageUrl
    }
    
    public func appending(_ gallery: Self) -> Self {
        .init(
            displayAuthor: displayAuthor,
            previews: previews + gallery.previews,
            nextPageUrl: gallery.nextPageUrl
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
            nextPageUrl: page.nextPageUrl
        )
    }
}

