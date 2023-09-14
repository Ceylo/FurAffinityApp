//
//  FAUserGallery.swift
//  
//
//  Created by Ceylo on 06/09/2023.
//

import Foundation
import FAPages

public struct FAUserGallery {
    public let displayAuthor: String
    public let previews: [FASubmissionPreview]
    
    public init(displayAuthor: String, previews: [FASubmissionPreview]) {
        self.displayAuthor = displayAuthor
        self.previews = previews
    }
    
    public static func url(for user: String) -> URL {
        FAUserGalleryPage.url(for: user)
    }
}

extension FAUserGallery {
    public init(_ page: FAUserGalleryPage) {
        self.init(
            displayAuthor: page.displayAuthor,
            previews: page.previews
                .compactMap { $0 }
                .map { FASubmissionPreview($0) }
        )
    }
}

