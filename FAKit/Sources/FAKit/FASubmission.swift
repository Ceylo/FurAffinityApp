//
//  File.swift
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
    public let author: String
    public let displayAuthor: String
    public let authorAvatarUrl: URL
    public let title: String
    public let htmlDescription: String
    
    public init(url: URL, previewImageUrl: URL, fullResolutionImageUrl: URL, author: String, displayAuthor: String, authorAvatarUrl: URL, title: String, htmlDescription: String) {
        self.url = url
        self.previewImageUrl = previewImageUrl
        self.fullResolutionImageUrl = fullResolutionImageUrl
        self.author = author
        self.displayAuthor = displayAuthor
        self.authorAvatarUrl = authorAvatarUrl
        self.title = title
        self.htmlDescription = htmlDescription.selfContainedFAHtml
    }
}

extension FASubmission {
    init(_ page: FASubmissionPage, url: URL) {
        self.init(url: url,
                  previewImageUrl: page.previewImageUrl,
                  fullResolutionImageUrl: page.fullResolutionImageUrl,
                  author: page.author,
                  displayAuthor: page.displayAuthor,
                  authorAvatarUrl: page.authorAvatarUrl,
                  title: page.title,
                  htmlDescription: page.htmlDescription)
    }
}
