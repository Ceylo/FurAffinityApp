//
//  FAJournalPageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FAJournalPageTests: XCTestCase {
    func testSubmissionPageWithComments_isParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/view/10516170/")!
        let data = testData("www.furaffinity.net:journal:10516170-withcomments.html")
        let page = await FAJournalPage(data: data, url: url)
        XCTAssertNotNil(page)
        
        let expectedComments: [FAPageComment] = [
            .visible(.init(cid: 59820550, indentation: 0, author: "fukothenimbat", displayAuthor: "FukoTheNimbat",
                           datetime: "Apr 3, 2023 12:01 AM", naturalDatetime: "2 weeks ago", htmlMessage: "Ill take one")),
            .visible(.init(cid: 59820552, indentation: 0, author: "zacharywulf", displayAuthor: "Zacharywulf",
                           datetime: "Apr 3, 2023 12:01 AM", naturalDatetime: "2 weeks ago", htmlMessage: "I want one!")),
            .visible(.init(cid: 59820567, indentation: 0, author: "leacrea", displayAuthor: "Leacrea",
                           datetime: "Apr 3, 2023 12:11 AM", naturalDatetime: "2 weeks ago", htmlMessage: "I’ll take one")),
            .visible(.init(cid: 59820573, indentation: 0, author: "thegrapedemon", displayAuthor: "TheGrapeDemon",
                           datetime: "Apr 3, 2023 12:17 AM", naturalDatetime: "2 weeks ago", htmlMessage: "I would love one please!! &lt;3")),
            .visible(.init(cid: 59820579, indentation: 0, author: "shadoweddraco", displayAuthor: "ShadowedDraco",
                           datetime: "Apr 3, 2023 12:22 AM", naturalDatetime: "2 weeks ago", htmlMessage: "i will take aslot")),
            .visible(.init(cid: 59820673, indentation: 0, author: "xaraphiel", displayAuthor: "Xaraphiel",
                           datetime: "Apr 3, 2023 02:34 AM", naturalDatetime: "2 weeks ago",
                           htmlMessage: "Awww I keep waking up and finding all slots are taken. I hate time zones 😭😅\n<br /> \n<br /> Congrats all who got upgrades 😇")),
            .visible(.init(cid: 59820831, indentation: 3, author: "flamekillaxxx", displayAuthor: "flamekillaXxX",
                           datetime: "Apr 3, 2023 06:37 AM", naturalDatetime: "2 weeks ago",
                           htmlMessage: "I know that feeling! Best of luck to us if there is another round \n<i class=\"smilie love\"></i>"))
        ]
        
        let expectedHtmlDescription = """
<div class="journal-content-container "> \n <div class="journal-content user-submitted-links">\n  what you will need to get one.\n  <br /> - if you got a sketch you can get an upgrade.\n  <br /> -comment on this Journal to get in line(ill work down the line and work in that order)\n  <br /> -make sure you have the funds to get a spot.\n  <br /> -if you have one more then one sketch you can have 3 at the most i can upgrade ( make sure you have the funds if your doing more then one)\n  <br /> -ill note you to get the ref and info to upgrade your pic. the farther your in line the longer will take to get to you, so PLZ try put aside the funds till i get to you in line.\n  <br /> -you will be paying $75 or more depending on what you want done.\n  <br /> for just you OC and no BG will $75 per OC.\n  <br /> BG and or extra stuff added will be $100 more or less.\n  <br /> \n  <br /> after this will go back to sketches then back to upgrades.\n  <br /> \n  <br /> depending on how much the person asks could take me more or less time to get to the next one in line.\n  <br /> so PLZ wait for not to get your info.\n  <br /> \n  <br /> GOOD LUCK TO EVERYONE.\n  <br /> \n  <br /> \n  <br /> 1. \n  <a href="/user/fukothenimbat" class="iconusername"><img src="//a.furaffinity.net/20230416/fukothenimbat.gif" align="middle" title="fukothenimbat" alt="fukothenimbat" />&nbsp;fukothenimbat</a>\n  <br /> \n  <br /> 2. \n  <a href="/user/zacharywulf" class="iconusername"><img src="//a.furaffinity.net/20230416/zacharywulf.gif" align="middle" title="zacharywulf" alt="zacharywulf" />&nbsp;zacharywulf</a>\n  <br /> \n  <br /> 3. \n  <a href="/user/leacrea" class="iconusername"><img src="//a.furaffinity.net/20230416/leacrea.gif" align="middle" title="leacrea" alt="leacrea" />&nbsp;leacrea</a>\n  <br /> \n  <br /> 4. \n  <a href="/user/thegrapedemon" class="iconusername"><img src="//a.furaffinity.net/20230416/thegrapedemon.gif" align="middle" title="thegrapedemon" alt="thegrapedemon" />&nbsp;thegrapedemon</a>\n  <br /> \n  <br /> 5. \n  <a href="/user/shadoweddraco" class="iconusername"><img src="//a.furaffinity.net/20230416/shadoweddraco.gif" align="middle" title="shadoweddraco" alt="shadoweddraco" />&nbsp;shadoweddraco</a>\n  <br /> \n  <br /> for not this will be the last one then going back to sketches then maybe open one more then back to one more upgrade but will see how things go.\n </div> \n</div>
"""
        
        let expectedPage = FAJournalPage(
            author: "rudragon",
            displayAuthor: "RUdragon",
            title: "UPGRADES ARE OPEN!!! 5",
            datetime: "Apr 2, 2023 11:59 PM",
            naturalDatetime: "2 weeks ago",
            htmlDescription: expectedHtmlDescription,
            comments: expectedComments,
            acceptsNewComments: true
        )
        
        XCTAssertEqual(expectedPage, page)
    }
    
    func testSubmissionPageWithCommentsDisabled_isParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/journal/10882268/")!
        let data = testData("www.furaffinity.net:journal:10882268-disabled-comments.html")
        let page = try await FAJournalPage(data: data, url: url).unwrap()
        
        XCTAssertEqual(page.acceptsNewComments, false)
    }
}
