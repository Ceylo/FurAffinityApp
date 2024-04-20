//
//  FAUserGalleryLikePage.swift
//  
//
//  Created by Ceylo on 31/08/2023.
//

import Foundation
import SwiftSoup

public struct FAUserGalleryLikePage {
    public let previews: [FASubmissionsPage.Submission?]
    public let displayAuthor: String
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
            
            let itemsQuery = "div#page-galleryscraps div.content section.gallery-section div.section-body div.submission-list section#gallery-gallery figure"
            let items = try siteContentNode.select(itemsQuery).array()
            async let previews = items.parallelMap { FASubmissionsPage.Submission($0) }
            
            let userNode = try siteContentNode.select(
                "userpage-nav-header userpage-nav-user-details h1 username"
            )
            self.displayAuthor = try String(userNode.text().dropFirst())
            self.previews = await previews
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}
