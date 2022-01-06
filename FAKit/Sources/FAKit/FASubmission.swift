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
        
        let htmlDescriptionPrefix = """
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
        <html lang="en" class="no-js" xmlns="http://www.w3.org/1999/xhtml">
        <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0" />
            <link type="text/css" rel="stylesheet" href="/themes/beta/css/ui_theme_dark.css" />
        </head>
        <body data-static-path="/themes/beta">
            <div class="section-body">
                <div class="submission-description user-submitted-links">
        """
        let htmlDescriptionSuffix = "</div></div></body></html>"
        let correctedDescription = (htmlDescriptionPrefix + htmlDescription + htmlDescriptionSuffix)
            .replacingOccurrences(of: "href=\"/", with: "href=\"https://www.furaffinity.net/")
            .replacingOccurrences(of: "src=\"//", with: "src=\"https://")
            .replacingOccurrences(of: "src=\"/", with: "src=\"https://www.furaffinity.net/")
        
        self.htmlDescription = correctedDescription
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
