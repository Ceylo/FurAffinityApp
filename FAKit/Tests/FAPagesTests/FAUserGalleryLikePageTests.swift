//
//  FAUserGalleryLikePageTests.swift
//  
//
//  Created by Ceylo on 31/08/2023.
//

import XCTest
@testable import FAPages

extension [FAFolderGroup] {
    func ignoringUUID() -> Self {
        map { $0.ignoringUUID() }
    }
}

extension FAFolderGroup {
    func ignoringUUID() -> Self {
        let folders = self.folders.map { $0.ignoringUUID() }
        return Self.init(title: title, folders: folders, id: UUID(uuid: UUID_NULL))
    }
}

extension FAFolder {
    func ignoringUUID() -> Self {
        Self.init(title: title, url: url, isActive: isActive, id: UUID(uuid: UUID_NULL))
    }
}

final class FAUserGalleryLikePageTests: XCTestCase {
    let tiaamaitoFolders: [FAFolderGroup] = [
        .init(title: "Gallery Folders", folders: [
            .init(title: "Main Gallery", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/")!, isActive: true),
            .init(title: "Scraps", url: URL(string: "https://www.furaffinity.net/scraps/tiaamaito/")!, isActive: false)
        ]),
        .init(title: "Personal", folders: [
            .init(title: "Chuvareu", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147920/Chuvareu")!, isActive: false),
            .init(title: "Chuvareu Comic (archieved)", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/292599/Chuvareu-Comic-archieved")!, isActive: false),
            .init(title: "Bakemono Family", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/418988/Bakemono-Family")!, isActive: false),
            .init(title: "chars as animals", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/456419/chars-as-animals")!, isActive: false),
            .init(title: "the tiniest lord", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566887/the-tiniest-lord")!, isActive: false),
            .init(title: "Ribbon Pooch & Co", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566888/Ribbon-Pooch-Co")!, isActive: false),
            .init(title: "Kijani", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566890/Kijani")!, isActive: false),
            .init(title: "Digital Pack", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566891/Digital-Pack")!, isActive: false),
        ]),
        .init(title: "Closed Species", folders: [
            .init(title: "Sushi Dogs", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566883/Sushi-Dogs")!, isActive: false),
            .init(title: "Griffia", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566884/Griffia")!, isActive: false),
            .init(title: "Memory Keepers", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/720355/Memory-Keepers")!, isActive: false),
        ]),
        .init(title: "for Sale", folders: [
            .init(title: "P2U", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/473101/P2U")!, isActive: false),
            .init(title: "Adopts", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/473103/Adopts")!, isActive: false),
            .init(title: "Traditional Pieces", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/495402/Traditional-Pieces")!, isActive: false),
            .init(title: "Other", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/547857/Other")!, isActive: false),
            .init(title: "Art Prints", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/684620/Art-Prints")!, isActive: false),
        ]),
        .init(title: "Patreon", folders: [
            .init(title: "2016", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/135452/2016")!, isActive: false),
            .init(title: "2017", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/297815/2017")!, isActive: false),
            .init(title: "2018", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/459438/2018")!, isActive: false),
            .init(title: "2019", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/613283/2019")!, isActive: false),
            .init(title: "2020", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/754413/2020")!, isActive: false),
            .init(title: "2021", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/937613/2021")!, isActive: false),
        ]),
        .init(title: "Commissions", folders: [
            .init(title: "standard (cell shading)", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147923/standard-cell-shading")!, isActive: false),
            .init(title: "clear (soft shading)", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147924/clear-soft-shading")!, isActive: false),
            .init(title: "basic (base colors)", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147925/basic-base-colors")!, isActive: false),
            .init(title: "reference sheet", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147927/reference-sheet")!, isActive: false),
            .init(title: "YCH", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147928/YCH")!, isActive: false),
            .init(title: "telegram stickers", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/415109/telegram-stickers")!, isActive: false),
            .init(title: "special", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/578261/special")!, isActive: false),
            .init(title: "old works", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147929/old-works")!, isActive: false),
        ])
    ]
    
    func testFirstGalleryPage_72itemsParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/gallery/tiaamaito/")!
        let data = testData("www.furaffinity.net:gallery:tiaamaito:.html")
        let asyncPage = await FAUserGalleryLikePage(data: data, url: url)
        let page = try XCTUnwrap(asyncPage)
        XCTAssertEqual(page.previews.count, 72)
        XCTAssertEqual(page.displayAuthor, "tiaamaito")
        
        let preview = FASubmissionsPage.Submission(
            sid: 59265003,
            url: URL(string: "https://www.furaffinity.net/view/59265003/")!,
            thumbnailUrl: URL(string: "https://t.furaffinity.net/59265003@300-1734913553.jpg")!,
            thumbnailWidthOnHeightRatio: 1.4705901,
            title: "CM - Houseboat",
            author: "tiaamaito",
            displayAuthor: "tiaamaito"
        )
        XCTAssertEqual(preview, page.previews[0])
        XCTAssertEqual(
            URL(string: "https://www.furaffinity.net/gallery/tiaamaito/2/")!,
            page.nextPageUrl
        )
        XCTAssertEqual(tiaamaitoFolders.ignoringUUID(), page.folderGroups.ignoringUUID())
    }
    
    func testEmptyGalleryPage_parsedWithNoContent() async throws {
        let url = URL(string: "https://www.furaffinity.net/gallery/furrycount/")!
        let data = testData("www.furaffinity.net:gallery:furrycount:.html")
        let asyncPage = await FAUserGalleryLikePage(data: data, url: url)
        let page = try XCTUnwrap(asyncPage)
        XCTAssertEqual(page.previews.count, 0)
        XCTAssertEqual(page.displayAuthor, "Furrycount")
        XCTAssertEqual(page.nextPageUrl, nil)
        XCTAssertEqual(page.folderGroups, [])
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
        XCTAssertEqual(page.folderGroups.count, 6)
    }
    
    func testFavoritesPage_72itemsParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/favorites/tiaamaito/")!
        let data = testData("www.furaffinity.net:favorites:tiaamaito:.html")
        let asyncPage = await FAUserGalleryLikePage(data: data, url: url)
        let page = try XCTUnwrap(asyncPage)
        XCTAssertEqual(page.previews.count, 72)
        XCTAssertEqual(page.displayAuthor, "tiaamaito")
        
        let preview = FASubmissionsPage.Submission(
            sid: 59039707,
            url: URL(string: "https://www.furaffinity.net/view/59039707/")!,
            thumbnailUrl: URL(string: "https://t.furaffinity.net/59039707@300-1733178293.jpg")!,
            thumbnailWidthOnHeightRatio: 1.081205,
            title: "WI - Comfort/No Hurt",
            author: "shiroganeryo",
            displayAuthor: "ShiroganeRyo"
        )
        XCTAssertEqual(preview, page.previews[0])
        XCTAssertEqual(
            URL(string: "https://www.furaffinity.net/favorites/tiaamaito/1528468491/next")!,
            page.nextPageUrl
        )
        XCTAssertEqual(page.folderGroups, [])
    }
}
