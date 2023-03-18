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
        let page = FASubmissionPage(data: data)
        XCTAssertNotNil(page)
        
        let htmlDescription = #"""
YCH for 
<a href="/user/lil-maj" class="iconusername"><img src="//a.furaffinity.net/20221211/lil-maj.gif" align="middle" title="lil-maj" alt="lil-maj">&nbsp;lil-maj</a> 
<br> 
<br> Cody © 
<a href="/user/lil-maj" class="iconusername"><img src="//a.furaffinity.net/20221211/lil-maj.gif" align="middle" title="lil-Maj" alt="lil-Maj">&nbsp;lil-Maj</a>
<br> 
<br> 
<br> 
<br> 
<br> 
<br> *******************************
<br> * 
<a class="auto_link named_url" href="http://ko-fi.com/J3J16KSH">Feed me with coffee?</a>
<br> * 
<a class="auto_link named_url" href="https://www.furaffinity.net/gallery/annetpeas/">My Gallery</a>
<br> * 
<a class="auto_link named_url" href="https://twitter.com/AnnetPeas_Art">Twitter</a>
"""#
        let expected = FASubmissionPage(
            previewImageUrl: URL(string: "https://t.furaffinity.net/49338772@600-1665402309.jpg")!,
            fullResolutionImageUrl: URL(string: "https://d.furaffinity.net/art/annetpeas/1665402309/1665402309.annetpeas_the_hookah_fa.png")!,
            widthOnHeightRatio: 1217 / 1280,
            author: "annetpeas",
            displayAuthor: "AnnetPeas",
            authorAvatarUrl: URL(string: "https://a.furaffinity.net/1670079651/annetpeas.gif")!,
            title: "The hookah",
            datetime: "Oct 10, 2022 08:45 AM",
            naturalDatetime: "2 months ago",
            htmlDescription: htmlDescription,
            isFavorite: false,
            favoriteUrl: URL(string: "https://www.furaffinity.net/fav/49338772/?key=57af11f57cd9a0d97575839f1ae07d2a775ae5af")!,
            comments: [])
        
        XCTAssertEqual(page, expected)
    }
    
    func testSubmissionPageWithHiddenComment_isParsed() throws {
        let data = testData("www.furaffinity.net:view:49917619-comment-hidden.html")
        let page = FASubmissionPage(data: data)
        XCTAssertNotNil(page)
        XCTAssertEqual(11, page?.comments.count)
    }
    
    func testSubmissionPageWithComments_isParsed() throws {
        let data = testData("www.furaffinity.net:view:48519387-comments.html")
        let page = FASubmissionPage(data: data)
        XCTAssertNotNil(page)
        let terrinissAvatarUrl = URL(string: "https://a.furaffinity.net/1616615925/terriniss.gif")!
        let expected: [FASubmissionPage.Comment] = [
            .init(cid: 166652793, indentation: 0, author: "terriniss", displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl,
                  datetime: "Aug 11, 2022 09:48 PM", naturalDatetime: "3 months ago", htmlMessage: "BID HERE \n<br> Moon"),
            .init(cid: 166653891, indentation: 3, author: "terriniss", displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl,
                  datetime: "Aug 11, 2022 10:58 PM", naturalDatetime: "3 months ago", htmlMessage: "SakuraSlowly (DA) - SB"),
            .init(cid: 166658565, indentation: 6, author: "terriniss", displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl,
                  datetime: "Aug 12, 2022 05:16 AM", naturalDatetime: "3 months ago", htmlMessage: "DeathPanda21 (da) - 55$"),
            .init(cid: 166663244, indentation: 9, author: "terriniss", displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl,
                  datetime: "Aug 12, 2022 12:33 PM", naturalDatetime: "3 months ago", htmlMessage: "ionightarts (DA) - 60"),
            .init(cid: 166652794, indentation: 0, author: "terriniss", displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl,
                  datetime: "Aug 11, 2022 09:48 PM", naturalDatetime: "3 months ago", htmlMessage: "BID HERE \n<br> Dawn"),
            .init(cid: 166656182, indentation: 3, author: "terriniss", displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl,
                  datetime: "Aug 12, 2022 01:48 AM", naturalDatetime: "3 months ago", htmlMessage: "Miss-You-Love (da) - SB"),
            .init(cid: 166658577, indentation: 6, author: "terriniss", displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl,
                  datetime: "Aug 12, 2022 05:17 AM", naturalDatetime: "3 months ago", htmlMessage: "LilNikkiBun (da) - 55$"),
            .init(cid: 166653340, indentation: 0, author: "rurudaspippen", displayAuthor: "RuruDasPippen",
                  authorAvatarUrl: URL(string: "https://a.furaffinity.net/1643948243/rurudaspippen.gif")!,
                  datetime: "Aug 11, 2022 10:23 PM", naturalDatetime: "3 months ago", htmlMessage: "Look at the babies!"),
            .init(cid: 166656573, indentation: 0, author: "fallen5592", displayAuthor: "fallen5592",
                  authorAvatarUrl: URL(string: "https://a.furaffinity.net/1631355052/fallen5592.gif")!,
                  datetime: "Aug 12, 2022 02:17 AM", naturalDatetime: "3 months ago", htmlMessage: "ooo... more intrestin, cute lil fellas ;p"),
            .init(cid: 166657876, indentation: 0, author: "alvienta", displayAuthor: "alvienta",
                  authorAvatarUrl: URL(string: "https://a.furaffinity.net/1637617140/alvienta.gif")!,
                  datetime: "Aug 12, 2022 04:08 AM", naturalDatetime: "3 months ago", htmlMessage: "these are gorgeous")
        ]
        
        XCTAssertEqual(expected, page?.comments)
    }
}
