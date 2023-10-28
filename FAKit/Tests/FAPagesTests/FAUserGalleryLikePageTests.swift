//
//  FAUserGalleryLikePageTests.swift
//  
//
//  Created by Ceylo on 31/08/2023.
//

import XCTest
@testable import FAPages

final class FAUserGalleryLikePageTests: XCTestCase {
    func testFirstGalleryPage_72itemsParsed() async throws {
        let data = testData("www.furaffinity.net:gallery:tiaamaito:.html")
        let asyncPage = await FAUserGalleryLikePage(data: data)
        let page = try XCTUnwrap(asyncPage)
        XCTAssertEqual(page.previews.count, 72)
        XCTAssertEqual(page.displayAuthor, "tiaamaito")
        
        let preview = FASubmissionsPage
            .Submission(sid: 53453723,
                        url: URL(string: "https://www.furaffinity.net/view/53453723/")!,
                        thumbnailUrl: URL(string: "https://t.furaffinity.net/53453723@300-1693154483.jpg")!,
                        thumbnailWidthOnHeightRatio: 1.4584,
                        title: "CM - Cute dogs and flowers 🐶🐶🌺",
                        author: "tiaamaito",
                        displayAuthor: "tiaamaito")
        XCTAssertEqual(preview, page.previews[0])
    }
    
    func testEmptyGalleryPage_parsedWithNoContent() async throws {
        let data = testData("www.furaffinity.net:gallery:furrycount:.html")
        let asyncPage = await FAUserGalleryLikePage(data: data)
        let page = try XCTUnwrap(asyncPage)
        XCTAssertEqual(page.previews.count, 0)
        XCTAssertEqual(page.displayAuthor, "Furrycount")
    }
}
