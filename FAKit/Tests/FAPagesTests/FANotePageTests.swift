//
//  FANotePageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FANotePageTests: XCTestCase {
    func testNote_returnsNoteDetails() throws {
        let data = testData("www.furaffinity.net:msg:pms-contents.html")
        let page = FANotePage(data: data)
        XCTAssertNotNil(page)
        
        let expected = FANotePage(
            author: "someuser", displayAuthor: "SomeUser",
            title: "RE: Fur Affinity app update",
            datetime: "May 10th, 2024, 04:41 AM",
            naturalDatetime: "9 months ago",
            htmlMessage: """
<i style="color: red;">\n <div class="noteWarningMessage noteWarningMessage--scam user-submitted-links"> \n  <div class="noteWarningMessage__icon"> \n   <img src="/themes/beta/img/icons/Error_l.png" /> \n  </div> \n  <div> \n   <h4>Do you know this person?</h4> Verify the username and profile before doing business with them! Scammers often attempt to impersonate well-known artists. \n   <br /> If you encounter something suspicious, please report it using a \n   <a href="/controls/troubletickets/">Trouble Ticket</a>. \n  </div> \n  <br />\n </div></i> Hey there,\n<br /> I hope you enjoyed the changes in the latest app version!\n<br /> If you'd like to see specific changes or have some troubles with it, please let me know! 💕\n<br /> \n<br /> Have a nice day 🎉
""",
            answerKey: "6338a73594650e0059a798fa9677bb9b3353e247"
        )
        XCTAssertEqual(expected, page)
    }
}
