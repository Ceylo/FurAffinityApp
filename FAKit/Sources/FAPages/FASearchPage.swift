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
    /// Ratings the account is allowed to search. FA renders the sidebar rating
    /// checkboxes `disabled` for the ones it restricts (e.g. General-only accounts
    /// can't toggle Mature/Adult).
    public let allowedRatings: Set<Rating>
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

            let ratingInputs = try doc.select("input[name^=rating-]")
            if ratingInputs.isEmpty() {
                // Defensive: no rating inputs found → stay optimistic (allow all).
                self.allowedRatings = Set(Rating.allCases)
            } else {
                self.allowedRatings = Set(try ratingInputs.compactMap { input -> Rating? in
                    guard !input.hasAttr("disabled") else { return nil }
                    return Rating(searchParamName: try input.attr("name"))
                })
            }
        } catch {
            logger.error("\(#file) - \(error)")
            throw error
        }
    }
}
