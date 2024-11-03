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
        
        let preview = FASubmissionsPage.Submission(
            sid: 58689926,
            url: URL(string: "https://www.furaffinity.net/view/58689926/")!,
            thumbnailUrl: URL(string: "https://t.furaffinity.net/58689926@400-1730507414.jpg")!,
            thumbnailWidthOnHeightRatio: 1.73507,
            title: "🧸 Fandom Pins Kickstarter ✨",
            author: "tiaamaito",
            displayAuthor: "tiaamaito"
        )
        XCTAssertEqual(preview, page.previews[0])
        XCTAssertEqual(
            URL(string: "https://www.furaffinity.net/gallery/tiaamaito/2/")!,
            page.nextPageUrl
        )
    }
    
    func testEmptyGalleryPage_parsedWithNoContent() async throws {
        let data = testData("www.furaffinity.net:gallery:furrycount:.html")
        let asyncPage = await FAUserGalleryLikePage(data: data)
        let page = try XCTUnwrap(asyncPage)
        XCTAssertEqual(page.previews.count, 0)
        XCTAssertEqual(page.displayAuthor, "Furrycount")
        XCTAssertEqual(page.nextPageUrl, nil)
    }
    
    func testScrapsPage_72itemsParsed() async throws {
        let data = testData("www.furaffinity.net:scraps:tiaamaito:.html")
        let asyncPage = await FAUserGalleryLikePage(data: data)
        let page = try XCTUnwrap(asyncPage)
        XCTAssertEqual(page.previews.count, 72)
        XCTAssertEqual(page.displayAuthor, "tiaamaito")
        
        let preview = FASubmissionsPage.Submission(
            sid: 56842400,
            url: URL(string: "https://www.furaffinity.net/view/56842400/")!,
            thumbnailUrl: URL(string: "https://t.furaffinity.net/56842400@300-1717205729.jpg")!,
            thumbnailWidthOnHeightRatio: 1.4988,
            title: "🏳️‍🌈 Pride YCH 🏳️‍⚧️ Auction CLOSED",
            author: "tiaamaito",
            displayAuthor: "tiaamaito"
        )
        XCTAssertEqual(preview, page.previews[0])
        XCTAssertEqual(
            URL(string: "https://www.furaffinity.net/scraps/tiaamaito/2/")!,
            page.nextPageUrl
        )
    }
    
    func testFavoritesPage_72itemsParsed() async throws {
        let data = testData("www.furaffinity.net:favorites:tiaamaito:.html")
        let asyncPage = await FAUserGalleryLikePage(data: data)
        let page = try XCTUnwrap(asyncPage)
        XCTAssertEqual(page.previews.count, 72)
        XCTAssertEqual(page.displayAuthor, "tiaamaito")
        
        let preview = FASubmissionsPage.Submission(
            sid: 58678021,
            url: URL(string: "https://www.furaffinity.net/view/58678021/")!,
            thumbnailUrl: URL(string: "https://t.furaffinity.net/58678021@400-1730425229.jpg")!,
            thumbnailWidthOnHeightRatio: 2.021366,
            title: "Reward - Oooo Spooky Month 👻",
            author: "shiroganeryo",
            displayAuthor: "ShiroganeRyo"
        )
        XCTAssertEqual(preview, page.previews[0])
        XCTAssertEqual(
            URL(string: "https://www.furaffinity.net/favorites/tiaamaito/1523944993/next")!,
            page.nextPageUrl
        )
    }
}
