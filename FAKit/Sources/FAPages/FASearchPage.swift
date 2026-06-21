//
//  FASearchPage.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2026.
//

import Foundation
import SwiftSoup

public struct FASearchPage: FAPage {
    public let submissions: [FASubmissionsPage.Submission?]
    /// `true` when the search ran with no query and the site fell back to showing
    /// recent uploads (the `#search-results.query-not-provided` warning state).
    public let displayingRecentUploads: Bool
}

extension FASearchPage {
    public init(data: Data, url: URL) throws {
        let state = signposter.beginInterval("Search Page Parsing")
        defer { signposter.endInterval("Search Page Parsing", state) }

        do {
            let string = String(decoding: data, as: UTF8.self)
            let doc = try SwiftSoup.parse(string, url.absoluteString)

            let items = try doc.select("section#gallery-search-results figure")
            self.submissions = try items.map { try FASubmissionsPage.Submission($0) }

            let resultsNode = try doc.select("#search-results").first()
            self.displayingRecentUploads = resultsNode?.hasClass("query-not-provided") ?? false
        } catch {
            logger.error("\(#file) - \(error)")
            throw error
        }
    }
}
