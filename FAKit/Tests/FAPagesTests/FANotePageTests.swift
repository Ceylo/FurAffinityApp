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
        
        let expected = FANotePage(author: "someuser", displayAuthor: "SomeUser",
                                  title: "RE: Title with some spéciäl çhãrāčtęrs",
                                  datetime: "Apr 7th, 2022, 11:58 AM",
                                  htmlMessage: "Message with some spéciäl çhãrāčtęrs.\n<br> And a newline!",
                                  answerKey: "84b24b5f34cdfaec56a3679144f6907a98576a57")
        XCTAssertEqual(expected, page)
    }
}
