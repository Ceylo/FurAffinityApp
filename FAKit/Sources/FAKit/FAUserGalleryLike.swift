//
//  FAUserGalleryLike.swift
//  
//
//  Created by Ceylo on 06/09/2023.
//

import Foundation
import FAPages

/// The representation for a gallery-like page (gallery, scraps, favorites)
public struct FAUserGalleryLike {
    public let displayAuthor: String
    public let previews: [FASubmissionPreview]
    
    public init(displayAuthor: String, previews: [FASubmissionPreview]) {
        self.displayAuthor = displayAuthor
        self.previews = previews
    }
}

extension FAUserGalleryLike {
    public init(_ page: FAUserGalleryLikePage) {
        self.init(
            displayAuthor: page.displayAuthor,
            previews: page.previews
                .compactMap { $0 }
                .map { FASubmissionPreview($0) }
        )
    }
}

