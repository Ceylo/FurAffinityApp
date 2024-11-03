//
//  FAUserGalleryLikePage.swift
//  
//
//  Created by Ceylo on 31/08/2023.
//

import Foundation
@preconcurrency import SwiftSoup

public struct FAUserGalleryLikePage: Sendable {
    public let previews: [FASubmissionsPage.Submission?]
    public let displayAuthor: String
    public let nextPageUrl: URL?
}

extension FAUserGalleryLikePage {
    public init?(data: Data) async {
        let state = signposter.beginInterval("User Gallery Parsing")
        defer { signposter.endInterval("User Gallery Parsing", state) }
        
        do {
            let string = String(decoding: data, as: UTF8.self)
            let doc = try SwiftSoup.parse(string)
            
            let siteContentNode = try doc.select(
                "html body div#main-window div#site-content"
            )
            let itemsQuery = "section.gallery-section div.section-body section figure"
            let items = try siteContentNode.select(itemsQuery)
            async let previews = items.parallelMap { FASubmissionsPage.Submission($0) }
            
            let userNode = try siteContentNode.select(
                "userpage-nav-header userpage-nav-user-details h1 username"
            )
            self.displayAuthor = try String(userNode.text().dropFirst())
            self.previews = await previews
            
            let navigationFormsQuery = "section.gallery-section div.section-body div.gallery-navigation div form"
            let nextButtonForm = try? siteContentNode
                .select(navigationFormsQuery)
                .first(where: {
                    try $0.text() == "Next"
                })
            if let nextButtonForm {
                let relativeUrl = try nextButtonForm.attr("action")
                self.nextPageUrl = try URL(unsafeString: FAURLs.homeUrl.absoluteString + relativeUrl)
            } else {
                self.nextPageUrl = nil
            }
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}
