//
//  FASubmissionPageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

extension [FAFolder] {
    func ignoringUUID() -> Self {
        map { $0.ignoringUUID() }
    }
}

extension FASubmissionPage {
    func ignoringUUID() -> Self {
        .init(
            previewImageUrl: previewImageUrl,
            fullResolutionMediaUrl: fullResolutionMediaUrl,
            widthOnHeightRatio: widthOnHeightRatio,
            metadata: metadata.ignoringUUID(),
            htmlDescription: htmlDescription,
            isFavorite: isFavorite,
            favoriteUrl: favoriteUrl,
            comments: comments,
            targetCommentId: targetCommentId,
            acceptsNewComments: acceptsNewComments
        )
    }
}

extension FASubmissionPage.Metadata {
    func ignoringUUID() -> Self {
        .init(
            title: title,
            author: author,
            displayAuthor: displayAuthor,
            datetime: datetime,
            naturalDatetime: naturalDatetime,
            viewCount: viewCount,
            commentCount: commentCount,
            favoriteCount: favoriteCount,
            rating: rating,
            category: category,
            species: species,
            gender: gender,
            size: size,
            fileSize: fileSize,
            keywords: keywords,
            folders: folders.ignoringUUID()
        )
    }
}

final class FASubmissionPageTests: XCTestCase {
    func testSubmissionPageWithoutComment_isParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/view/49338772/")!
        let data = testData("www.furaffinity.net:view:49338772-nocomment.html")
        let page = try await FASubmissionPage(data: data, url: url).unwrap()
        
        let htmlDescription = "YCH for \n<a href=\"/user/lil-maj\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20250302/lil-maj.gif\" align=\"middle\" title=\"lil-maj\" alt=\"lil-maj\" />&nbsp;lil-maj</a> \n<br /> \n<br /> Cody © \n<a href=\"/user/lil-maj\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20250302/lil-maj.gif\" align=\"middle\" title=\"lil-Maj\" alt=\"lil-Maj\" />&nbsp;lil-Maj</a>\n<br /> \n<br /> \n<br /> \n<br /> \n<br /> \n<br /> *******************************\n<br /> * \n<a class=\"auto_link named_url\" href=\"http://ko-fi.com/J3J16KSH\">Feed me with coffee?</a>\n<br /> * \n<a class=\"auto_link named_url\" href=\"https://www.furaffinity.net/gallery/annetpeas/\">My Gallery</a>\n<br /> * \n<a class=\"auto_link named_url\" href=\"https://twitter.com/AnnetPeas_Art\">Twitter</a>"
        let expected = FASubmissionPage(
            previewImageUrl: URL(string: "https://t.furaffinity.net/49338772@600-1665402309.jpg")!,
            fullResolutionMediaUrl: URL(string: "https://d.furaffinity.net/art/annetpeas/1665402309/1665402309.annetpeas_the_hookah_fa.png")!,
            widthOnHeightRatio: 1217 / 1280,
            metadata: .init(
                title: "The hookah",
                author: "annetpeas",
                displayAuthor: "AnnetPeas",
                datetime: "Oct 10, 2022 02:45 PM",
                naturalDatetime: "2 years ago",
                viewCount: 706,
                commentCount: 0,
                favoriteCount: 67,
                rating: .general,
                category: "Artwork (Digital) / All",
                species: "Rabbit / Hare",
                gender: "Female",
                size: "1217 x 1280",
                fileSize: "1.22 MB",
                keywords: ["lil-maj", "cody", "female", "girl", "rabbit", "cute", "chibi", "annetpeas", "smoke", "smoking", "hookah"],
                folders: [.init(
                    title: "My arts - 2022",
                    url: URL(string: "https://www.furaffinity.net/gallery/annetpeas/folder/1069672/2022/")!,
                    isActive: false
                )]
            ),
            htmlDescription: htmlDescription,
            isFavorite: false,
            favoriteUrl: URL(string: "https://www.furaffinity.net/fav/49338772/?key=12a5f243b46625d69903529353b7a9805815a1d6")!,
            comments: [],
            targetCommentId: nil,
            acceptsNewComments: true
        )
        
        XCTAssertEqual(page.ignoringUUID(), expected.ignoringUUID())
    }
    
    func testSubmissionPageWithCommentsDisabled_isParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/view/52209828/")!
        let data = testData("www.furaffinity.net:view:52209828-disabled-comments.html")
        let page = try await FASubmissionPage(data: data, url: url).unwrap()
        
        XCTAssertEqual(page.acceptsNewComments, false)
    }
    
    func testSubmissionPageWithHiddenComment_isParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/view/49917619/")!
        let data = testData("www.furaffinity.net:view:49917619-comment-hidden.html")
        let page = try await FASubmissionPage(data: data, url: url).unwrap()
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
    
    func testSubmissionPageWithComments_isParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/view/48519387/#cid:166652794")!
        let data = testData("www.furaffinity.net:view:48519387-comments.html")
        let page = try await FASubmissionPage(data: data, url: url).unwrap()
        let expected: [FAPageComment] = [
            .visible(.init(cid: 166652793, indentation: 0, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 12, 2022 03:48 AM", naturalDatetime: "2 years ago", htmlMessage: "BID HERE \n<br /> Moon")),
            .visible(.init(cid: 166653891, indentation: 3, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 12, 2022 04:58 AM", naturalDatetime: "2 years ago", htmlMessage: "SakuraSlowly (DA) - SB")),
            .visible(.init(cid: 166658565, indentation: 6, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 12, 2022 11:16 AM", naturalDatetime: "2 years ago", htmlMessage: "DeathPanda21 (da) - 55$")),
            .visible(.init(cid: 166663244, indentation: 9, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 12, 2022 06:33 PM", naturalDatetime: "2 years ago", htmlMessage: "ionightarts (DA) - 60")),
            .visible(.init(cid: 166652794, indentation: 0, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 12, 2022 03:48 AM", naturalDatetime: "2 years ago", htmlMessage: "BID HERE \n<br /> Dawn")),
            .visible(.init(cid: 166656182, indentation: 3, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 12, 2022 07:48 AM", naturalDatetime: "2 years ago", htmlMessage: "Miss-You-Love (da) - SB")),
            .visible(.init(cid: 166658577, indentation: 6, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "Aug 12, 2022 11:17 AM", naturalDatetime: "2 years ago", htmlMessage: "LilNikkiBun (da) - 55$")),
            .visible(.init(cid: 166653340, indentation: 0, author: "rurudaspippen", displayAuthor: "RuruDasPippen",
                           datetime: "Aug 12, 2022 04:23 AM", naturalDatetime: "2 years ago", htmlMessage: "Look at the babies!")),
            .visible(.init(cid: 166656573, indentation: 0, author: "fallen5592", displayAuthor: "fallen5592",
                           datetime: "Aug 12, 2022 08:17 AM", naturalDatetime: "2 years ago", htmlMessage: "ooo... more intrestin, cute lil fellas ;p")),
            .visible(.init(cid: 166657876, indentation: 0, author: "alvienta", displayAuthor: "alvienta",
                           datetime: "Aug 12, 2022 10:08 AM", naturalDatetime: "2 years ago", htmlMessage: "these are gorgeous"))
        ]
        
        XCTAssertEqual(expected, page.comments)
        XCTAssertEqual(166652794, page.targetCommentId)
    }
}
