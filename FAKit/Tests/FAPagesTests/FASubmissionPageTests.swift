//
//  FASubmissionPageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FASubmissionPageTests: XCTestCase {
    func testSubmissionPageWithoutComment_isParsed() throws {
        let data = testData("www.furaffinity.net:view:49338772-nocomment.html")
        let page = try XCTUnwrap(FASubmissionPage(data: data))
        
        let htmlDescription = "YCH for \n<a href=\"/user/lil-maj\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221211/lil-maj.gif\" align=\"middle\" title=\"lil-maj\" alt=\"lil-maj\" />&nbsp;lil-maj</a> \n<br /> \n<br /> Cody © \n<a href=\"/user/lil-maj\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221211/lil-maj.gif\" align=\"middle\" title=\"lil-Maj\" alt=\"lil-Maj\" />&nbsp;lil-Maj</a>\n<br /> \n<br /> \n<br /> \n<br /> \n<br /> \n<br /> *******************************\n<br /> * \n<a class=\"auto_link named_url\" href=\"http://ko-fi.com/J3J16KSH\">Feed me with coffee?</a>\n<br /> * \n<a class=\"auto_link named_url\" href=\"https://www.furaffinity.net/gallery/annetpeas/\">My Gallery</a>\n<br /> * \n<a class=\"auto_link named_url\" href=\"https://twitter.com/AnnetPeas_Art\">Twitter</a>"
        let expected = FASubmissionPage(
            previewImageUrl: URL(string: "https://t.furaffinity.net/49338772@600-1665402309.jpg")!,
            fullResolutionImageUrl: URL(string: "https://d.furaffinity.net/art/annetpeas/1665402309/1665402309.annetpeas_the_hookah_fa.png")!,
            widthOnHeightRatio: 1217 / 1280,
            author: "annetpeas",
            displayAuthor: "AnnetPeas",
            title: "The hookah",
            datetime: "Oct 10, 2022 08:45 AM",
            naturalDatetime: "2 months ago",
            htmlDescription: htmlDescription,
            isFavorite: false,
            favoriteCount: 67,
            favoriteUrl: URL(string: "https://www.furaffinity.net/fav/49338772/?key=57af11f57cd9a0d97575839f1ae07d2a775ae5af")!,
            comments: [])
        
        XCTAssertEqual(page, expected)
    }
    
    func testSubmissionPageWithHiddenComment_isParsed() throws {
        let data = testData("www.furaffinity.net:view:49917619-comment-hidden.html")
        let page = try XCTUnwrap(FASubmissionPage(data: data))
        XCTAssertEqual(12, page.comments.count)
        
        for (index, comment) in page.comments.enumerated() {
            switch comment {
            case .hidden:
                XCTAssertEqual(
                    comment,
                    .hidden(.init(cid: 168829732, indentation: 6, htmlMessage: "Comment hidden by its owner"))
                )
            case .visible:
                XCTAssertNotEqual(index, 6)
            }
        }
    }
    
    func testSubmissionPageWithComments_isParsed() throws {
        let data = testData("www.furaffinity.net:view:48519387-comments.html")
        let page = try XCTUnwrap(FASubmissionPage(data: data))
        let expected: [FAPageComment] = [
            .visible(.init(cid: 166652793, indentation: 0, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 11, 2022 09:48 PM", naturalDatetime: "3 months ago", htmlMessage: "BID HERE \n<br /> Moon")),
            .visible(.init(cid: 166653891, indentation: 3, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 11, 2022 10:58 PM", naturalDatetime: "3 months ago", htmlMessage: "SakuraSlowly (DA) - SB")),
            .visible(.init(cid: 166658565, indentation: 6, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 12, 2022 05:16 AM", naturalDatetime: "3 months ago", htmlMessage: "DeathPanda21 (da) - 55$")),
            .visible(.init(cid: 166663244, indentation: 9, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 12, 2022 12:33 PM", naturalDatetime: "3 months ago", htmlMessage: "ionightarts (DA) - 60")),
            .visible(.init(cid: 166652794, indentation: 0, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 11, 2022 09:48 PM", naturalDatetime: "3 months ago", htmlMessage: "BID HERE \n<br /> Dawn")),
            .visible(.init(cid: 166656182, indentation: 3, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 12, 2022 01:48 AM", naturalDatetime: "3 months ago", htmlMessage: "Miss-You-Love (da) - SB")),
            .visible(.init(cid: 166658577, indentation: 6, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 12, 2022 05:17 AM", naturalDatetime: "3 months ago", htmlMessage: "LilNikkiBun (da) - 55$")),
            .visible(.init(cid: 166653340, indentation: 0, author: "rurudaspippen", displayAuthor: "RuruDasPippen",
                           datetime: "Aug 11, 2022 10:23 PM", naturalDatetime: "3 months ago", htmlMessage: "Look at the babies!")),
            .visible(.init(cid: 166656573, indentation: 0, author: "fallen5592", displayAuthor: "fallen5592",
                           datetime: "Aug 12, 2022 02:17 AM", naturalDatetime: "3 months ago", htmlMessage: "ooo... more intrestin, cute lil fellas ;p")),
            .visible(.init(cid: 166657876, indentation: 0, author: "alvienta", displayAuthor: "alvienta",
                           datetime: "Aug 12, 2022 04:08 AM", naturalDatetime: "3 months ago", htmlMessage: "these are gorgeous"))
        ]
        
        XCTAssertEqual(expected, page.comments)
    }
}
