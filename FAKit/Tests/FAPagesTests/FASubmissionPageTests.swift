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
}
