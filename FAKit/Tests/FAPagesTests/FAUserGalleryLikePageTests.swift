//
//  FAUserGalleryLikePageTests.swift
//  
//
//  Created by Ceylo on 31/08/2023.
//

import XCTest
@testable import FAPages

final class FAUserGalleryLikePageTests: XCTestCase {
    let tiaamaitoFolders: [FAFolderItem] = [
        .section(title: "Gallery Folders"),
        .folder(title: "❯❯ Main Gallery", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/")!),
        .folder(title: "Scraps", url: URL(string: "https://www.furaffinity.net/scraps/tiaamaito/")!),
        .section(title: "Personal"),
        .folder(title: "Chuvareu", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147920/Chuvareu")!),
        .folder(title: "Chuvareu Comic (archieved)", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/292599/Chuvareu-Comic-archieved")!),
        .folder(title: "Bakemono Family", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/418988/Bakemono-Family")!),
        .folder(title: "chars as animals", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/456419/chars-as-animals")!),
        .folder(title: "the tiniest lord", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566887/the-tiniest-lord")!),
        .folder(title: "Ribbon Pooch & Co", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566888/Ribbon-Pooch-Co")!),
        .folder(title: "Kijani", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566890/Kijani")!),
        .folder(title: "Digital Pack", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566891/Digital-Pack")!),
        .section(title: "Closed Species"),
        .folder(title: "Sushi Dogs", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566883/Sushi-Dogs")!),
        .folder(title: "Griffia", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566884/Griffia")!),
        .folder(title: "Memory Keepers", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/720355/Memory-Keepers")!),
        .section(title: "for Sale"),
        .folder(title: "P2U", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/473101/P2U")!),
        .folder(title: "Adopts", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/473103/Adopts")!),
        .folder(title: "Traditional Pieces", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/495402/Traditional-Pieces")!),
        .folder(title: "Other", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/547857/Other")!),
        .folder(title: "Art Prints", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/684620/Art-Prints")!),
        .section(title: "Patreon"),
        .folder(title: "2016", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/135452/2016")!),
        .folder(title: "2017", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/297815/2017")!),
        .folder(title: "2018", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/459438/2018")!),
        .folder(title: "2019", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/613283/2019")!),
        .folder(title: "2020", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/754413/2020")!),
        .folder(title: "2021", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/937613/2021")!),
        .section(title: "Commissions"),
        .folder(title: "standard (cell shading)", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147923/standard-cell-shading")!),
        .folder(title: "clear (soft shading)", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147924/clear-soft-shading")!),
        .folder(title: "basic (base colors)", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147925/basic-base-colors")!),
        .folder(title: "reference sheet", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147927/reference-sheet")!),
        .folder(title: "YCH", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147928/YCH")!),
        .folder(title: "telegram stickers", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/415109/telegram-stickers")!),
        .folder(title: "special", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/578261/special")!),
        .folder(title: "old works", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147929/old-works")!),
    ]
    
    func testFirstGalleryPage_72itemsParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/gallery/tiaamaito/")!
        let data = testData("www.furaffinity.net:gallery:tiaamaito:.html")
        let asyncPage = await FAUserGalleryLikePage(data: data, url: url)
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
        XCTAssertEqual(tiaamaitoFolders, page.folderItems)
    }
    
    func testEmptyGalleryPage_parsedWithNoContent() async throws {
        let url = URL(string: "https://www.furaffinity.net/gallery/furrycount/")!
        let data = testData("www.furaffinity.net:gallery:furrycount:.html")
        let asyncPage = await FAUserGalleryLikePage(data: data, url: url)
        let page = try XCTUnwrap(asyncPage)
        XCTAssertEqual(page.previews.count, 0)
        XCTAssertEqual(page.displayAuthor, "Furrycount")
        XCTAssertEqual(page.nextPageUrl, nil)
        XCTAssertEqual(page.folderItems, [])
    }
    
    func testScrapsPage_72itemsParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/scraps/tiaamaito/")!
        let data = testData("www.furaffinity.net:scraps:tiaamaito:.html")
        let asyncPage = await FAUserGalleryLikePage(data: data, url: url)
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
        XCTAssertEqual(page.folderItems.count, 38)
    }
    
    func testFavoritesPage_72itemsParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/favorites/tiaamaito/")!
        let data = testData("www.furaffinity.net:favorites:tiaamaito:.html")
        let asyncPage = await FAUserGalleryLikePage(data: data, url: url)
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
        XCTAssertEqual(page.folderItems, [])
    }
}
