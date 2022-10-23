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
<a href="/user/lil-maj" class="iconusername"><img src="//a.furaffinity.net/20221023/lil-maj.gif" align="middle" title="lil-maj" alt="lil-maj">&nbsp;lil-maj</a> 
<br> 
<br> Cody © 
<a href="/user/lil-maj" class="iconusername"><img src="//a.furaffinity.net/20221023/lil-maj.gif" align="middle" title="lil-Maj" alt="lil-Maj">&nbsp;lil-Maj</a>
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
            author: "annetpeas",
            displayAuthor: "AnnetPeas",
            authorAvatarUrl: URL(string: "https://a.furaffinity.net/1663186682/annetpeas.gif")!,
            title: "The hookah",
            htmlDescription: htmlDescription,
            isFavorite: false,
            favoriteUrl: URL(string: "https://www.furaffinity.net/fav/49338772/?key=c9f6a9b5ebbcc70acdfbaa835433bef60167fcee")!,
            comments: [])
        
        XCTAssertEqual(page, expected)
    }
    
    func testSubmissionPageWithComment_isParsed() throws {
        let data = testData("www.furaffinity.net:view:48519387-comments.html")
        let page = FASubmissionPage(data: data)
        XCTAssertNotNil(page)
        let terrinissAvatarUrl = URL(string: "https//a.furaffinity.net/1616615925/terriniss.gif")!
        let expected: [FASubmissionComment] = [
            .init(cid: 166652793, parentCid: nil, author: "terriniss", displayAuthor: "Terriniss",
                  authorAvatarUrl: terrinissAvatarUrl, datetime: "2 months ago", htmlMessage: "BID HERE \n<br> Moon"),
            .init(cid: 166653891, parentCid: 166652793, author: "terriniss", displayAuthor: "Terriniss",
                  authorAvatarUrl: terrinissAvatarUrl, datetime: "2 months ago", htmlMessage: "SakuraSlowly (DA) - SB"),
            .init(cid: 166658565, parentCid: 166653891, author: "terriniss", displayAuthor: "Terriniss",
                  authorAvatarUrl: terrinissAvatarUrl, datetime: "2 months ago", htmlMessage: "DeathPanda21 (da) - 55$"),
            .init(cid: 166663244, parentCid: 166658565, author: "terriniss", displayAuthor: "Terriniss",
                  authorAvatarUrl: terrinissAvatarUrl, datetime: "2 months ago", htmlMessage: "ionightarts (DA) - 60"),
            .init(cid: 166652794, parentCid: nil, author: "terriniss", displayAuthor: "Terriniss",
                  authorAvatarUrl: terrinissAvatarUrl, datetime: "2 months ago", htmlMessage: "BID HERE \n<br> Dawn"),
            .init(cid: 166656182, parentCid: 166652794, author: "terriniss", displayAuthor: "Terriniss",
                  authorAvatarUrl: terrinissAvatarUrl, datetime: "2 months ago", htmlMessage: "Miss-You-Love (da) - SB"),
            .init(cid: 166658577, parentCid: 166656182, author: "terriniss", displayAuthor: "Terriniss",
                  authorAvatarUrl: terrinissAvatarUrl, datetime: "2 months ago", htmlMessage: "LilNikkiBun (da) - 55$"),
            .init(cid: 166653340, parentCid: nil, author: "rurudaspippen", displayAuthor: "RuruDasPippen",
                  authorAvatarUrl: URL(string: "https//a.furaffinity.net/1643948243/rurudaspippen.gif")!, datetime: "2 months ago",
                  htmlMessage: "Look at the babies!"),
            .init(cid: 166656573, parentCid: nil, author: "fallen5592", displayAuthor: "fallen5592",
                  authorAvatarUrl: URL(string: "https//a.furaffinity.net/1631355052/fallen5592.gif")!, datetime: "2 months ago",
                  htmlMessage: "ooo... more intrestin, cute lil fellas ;p"),
            .init(cid: 166657876, parentCid: nil, author: "alvienta", displayAuthor: "alvienta",
                  authorAvatarUrl: URL(string: "https//a.furaffinity.net/1637617140/alvienta.gif")!, datetime: "2 months ago",
                  htmlMessage: "these are gorgeous")
        ]
        
        XCTAssertEqual(expected, page?.comments)
    }
}
