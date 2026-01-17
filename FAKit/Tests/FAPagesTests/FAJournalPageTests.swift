//
//  FAJournalPageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FAJournalPageTests: XCTestCase {
    func testSubmissionPageWithComments_isParsed() throws {
        let url = URL(string: "https://www.furaffinity.net/journal/10516170/")!
        let data = testData("www.furaffinity.net:journal:10516170-withcomments.html")
        let page = try FAJournalPage(data: data, url: url)
        
        let expectedComments: [FAPageComment] = [
            .visible(.init(cid: 59820550, indentation: 0, author: "fukothenimbat", displayAuthor: "FukoTheNimbat",
                           datetime: "April 3, 2023 07:01:13 AM", naturalDatetime: "3 years ago", htmlMessage: "Ill take one")),
            .visible(.init(cid: 59820552, indentation: 0, author: "zacharywulf", displayAuthor: "Zacharywulf",
                           datetime: "April 3, 2023 07:01:41 AM", naturalDatetime: "3 years ago", htmlMessage: "I want one!")),
            .visible(.init(cid: 59820567, indentation: 0, author: "leacrea", displayAuthor: "Leacrea",
                           datetime: "April 3, 2023 07:11:23 AM", naturalDatetime: "3 years ago", htmlMessage: "I’ll take one")),
            .visible(.init(cid: 59820573, indentation: 0, author: "thegrapedemon", displayAuthor: "That_SkyHope",
                           datetime: "April 3, 2023 07:17:01 AM", naturalDatetime: "3 years ago", htmlMessage: "I would love one please!! &lt;3")),
            .visible(.init(cid: 59820579, indentation: 0, author: "shadoweddraco", displayAuthor: "ShadowedDraco",
                           datetime: "April 3, 2023 07:22:30 AM", naturalDatetime: "3 years ago", htmlMessage: "i will take aslot")),
            .visible(.init(cid: 59820673, indentation: 0, author: "xaraphiel", displayAuthor: "Xaraphiel",
                           datetime: "April 3, 2023 09:34:15 AM", naturalDatetime: "3 years ago",
                           htmlMessage: "Awww I keep waking up and finding all slots are taken. I hate time zones 😭😅\n<br /> \n<br /> Congrats all who got upgrades 😇")),
            .visible(.init(cid: 59820831, indentation: 3, author: "flamekillaxxx", displayAuthor: "flamekillaXxX",
                           datetime: "April 3, 2023 01:37:54 PM", naturalDatetime: "3 years ago",
                           htmlMessage: "I know that feeling! Best of luck to us if there is another round \n<i class=\"smilie love\"></i>"))
        ]
        
        let expectedHtmlDescription = """
<div class="journal-content-container "> 
 <div class="journal-content user-submitted-links">
  what you will need to get one.
  <br /> - if you got a sketch you can get an upgrade.
  <br /> -comment on this Journal to get in line(ill work down the line and work in that order)
  <br /> -make sure you have the funds to get a spot.
  <br /> -if you have one more then one sketch you can have 3 at the most i can upgrade ( make sure you have the funds if your doing more then one)
  <br /> -ill note you to get the ref and info to upgrade your pic. the farther your in line the longer will take to get to you, so PLZ try put aside the funds till i get to you in line.
  <br /> -you will be paying $75 or more depending on what you want done.
  <br /> for just you OC and no BG will $75 per OC.
  <br /> BG and or extra stuff added will be $100 more or less.
  <br /> 
  <br /> after this will go back to sketches then back to upgrades.
  <br /> 
  <br /> depending on how much the person asks could take me more or less time to get to the next one in line.
  <br /> so PLZ wait for not to get your info.
  <br /> 
  <br /> GOOD LUCK TO EVERYONE.
  <br /> 
  <br /> 
  <br /> 1. 
  <a href="/user/fukothenimbat" class="iconusername"><img src="//a.furaffinity.net/20260117/fukothenimbat.gif" align="middle" title="fukothenimbat" alt="fukothenimbat" />&nbsp;fukothenimbat</a>
  <br /> 
  <br /> 2. 
  <a href="/user/zacharywulf" class="iconusername"><img src="//a.furaffinity.net/20260117/zacharywulf.gif" align="middle" title="zacharywulf" alt="zacharywulf" />&nbsp;zacharywulf</a>
  <br /> 
  <br /> 3. 
  <a href="/user/leacrea" class="iconusername"><img src="//a.furaffinity.net/20260117/leacrea.gif" align="middle" title="leacrea" alt="leacrea" />&nbsp;leacrea</a>
  <br /> 
  <br /> 4. 
  <a href="/user/thegrapedemon" class="iconusername"><img src="//a.furaffinity.net/20260117/thegrapedemon.gif" align="middle" title="thegrapedemon" alt="thegrapedemon" />&nbsp;thegrapedemon</a>
  <br /> 
  <br /> 5. 
  <a href="/user/shadoweddraco" class="iconusername"><img src="//a.furaffinity.net/20260117/shadoweddraco.gif" align="middle" title="shadoweddraco" alt="shadoweddraco" />&nbsp;shadoweddraco</a>
  <br /> 
  <br /> for not this will be the last one then going back to sketches then maybe open one more then back to one more upgrade but will see how things go.
 </div> 
</div>
"""
        
        let expectedPage = FAJournalPage(
            author: "rudragon",
            displayAuthor: "RUdragon",
            title: "UPGRADES ARE OPEN!!! 5",
            datetime: "April 3, 2023 06:59:20 AM",
            naturalDatetime: "3 years ago",
            htmlDescription: expectedHtmlDescription,
            comments: expectedComments,
            targetCommentId: nil,
            acceptsNewComments: true
        )
        
        XCTAssertEqual(expectedPage, page)
        XCTAssertEqual(expectedPage.author, page.author)
        XCTAssertEqual(expectedPage.displayAuthor, page.displayAuthor)
        XCTAssertEqual(expectedPage.title, page.title)
        XCTAssertEqual(expectedPage.datetime, page.datetime)
        XCTAssertEqual(expectedPage.naturalDatetime, page.naturalDatetime)
        XCTAssertEqual(expectedPage.htmlDescription, page.htmlDescription)
        XCTAssertEqual(expectedPage.comments, page.comments)
        XCTAssertEqual(expectedPage.targetCommentId, page.targetCommentId)
        XCTAssertEqual(expectedPage.acceptsNewComments, page.acceptsNewComments)
    }
    
    func testSubmissionPageWithCommentsDisabled_isParsed() throws {
        let url = URL(string: "https://www.furaffinity.net/journal/10882268/")!
        let data = testData("www.furaffinity.net:journal:10882268-disabled-comments.html")
        let page = try FAJournalPage(data: data, url: url)
        
        XCTAssertEqual(page.acceptsNewComments, false)
    }
}
