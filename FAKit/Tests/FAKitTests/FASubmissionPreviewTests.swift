//
//  FASubmissionPreviewTests.swift
//  FAKit
//

import Testing
import Foundation
import FAKit

struct FASubmissionPreviewTests {
    @Test func codableRoundTrip() throws {
        let preview = FASubmissionPreview(
            sid: 44188741,
            url: URL(string: "https://www.furaffinity.net/view/44188741/")!,
            thumbnailUrl: URL(string: "https://t.furaffinity.net/44188741@200-1637084699.jpg")!,
            thumbnailWidthOnHeightRatio: 0.81,
            title: "Commission for Someone",
            author: "someone",
            displayAuthor: "Someone",
            rating: .mature
        )
        let decoded = try JSONDecoder().decode(FASubmissionPreview.self, from: JSONEncoder().encode(preview))
        #expect(decoded == preview)
    }
}
