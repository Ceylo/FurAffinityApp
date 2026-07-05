//
//  FASearchPageTests.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2026.
//

import Testing
import Foundation
@testable import FAPages

struct FASearchPageTests {
    @Test
    func recentUploadsSearch_72SubmissionsParsed() throws {
        let data = testData("www.furaffinity.net:search:")
        let page = try FASearchPage(data: data, url: FAURLs.searchUrl)
        #expect(page.submissions.count == 72)
        #expect(page.displayingRecentUploads == true)
        // The fixture was captured on a General-only account: FA renders the
        // Mature/Adult rating checkboxes `disabled`.
        #expect(page.allowedRatings == [.general])

        let submission = FASubmissionsPage.Submission(
            sid: 65413735,
            url: URL(string: "https://www.furaffinity.net/view/65413735/")!,
            thumbnailUrl: URL(string: "https://t.furaffinity.net/65413735@400-1781992882.jpg")!,
            thumbnailWidthOnHeightRatio: 328.0 / 200.0,
            title: "CM: Escaping",
            author: "razor-z",
            displayAuthor: "Razzyk",
            rating: .general
        )
        #expect(page.submissions[0] == submission)
    }
}
