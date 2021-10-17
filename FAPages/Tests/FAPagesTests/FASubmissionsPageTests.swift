//
//  FASubmissionsPageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FASubmissionsPageTests: XCTestCase {
    func testFirstSubmissionsPage_72SubmissionsParsed() throws {
        let loggedInHtml = htmlPath("www.furaffinity.net:msg:submissions-firstpage")
        let data = try Data(contentsOf: loggedInHtml)
        let page = FASubmissionsPage(data: data)
        XCTAssertNotNil(page)
        XCTAssertEqual(page?.submissions.count, 72)
        
        let submission = FASubmissionsPage
            .Submission(sid: 44196991,
                        url: URL(string: "https://www.furaffinity.net/view/44196991/")!,
                        thumbnailUrl: URL(string: "https://t.furaffinity.net/44196991@200-1634457867.jpg")!,
                        title: "YCH Reminder! <3",
                        author: "annetpeas",
                        displayAuthor: "AnnetPeas")
        XCTAssertEqual(submission, page?.submissions[0])
        
    }
    
    func testFirstSubmissionsPage_NextPageUrlParsed() throws {
        let loggedInHtml = htmlPath("www.furaffinity.net:msg:submissions-firstpage")
        let data = try Data(contentsOf: loggedInHtml)
        let page = FASubmissionsPage(data: data)
        XCTAssertNotNil(page)
        XCTAssertNil(page?.previousPageUrl)
        XCTAssertEqual(page?.nextPageUrl?.absoluteString, "https://www.furaffinity.net/msg/submissions/new~43830292@72/")
    }
    
    func testLastSubmissionsPage_PreviousPageUrlParsed() throws {
        let loggedInHtml = htmlPath("www.furaffinity.net:msg:submissions-lastpage")
        let data = try Data(contentsOf: loggedInHtml)
        let page = FASubmissionsPage(data: data)
        XCTAssertNotNil(page)
        XCTAssertNil(page?.nextPageUrl)
        XCTAssertEqual(page?.previousPageUrl?.absoluteString, "https://www.furaffinity.net/msg/submissions/new~35929848@72/")
    }
    
    func testMiddleSubmissionsPage_PreviousAndNextPageUrlsParsed() throws {
        let loggedInHtml = htmlPath("www.furaffinity.net:msg:submissions-middlepage")
        let data = try Data(contentsOf: loggedInHtml)
        let page = FASubmissionsPage(data: data)
        XCTAssertNotNil(page)
        XCTAssertEqual(page?.nextPageUrl?.absoluteString, "https://www.furaffinity.net/msg/submissions/new~43704007@48/")
        XCTAssertEqual(page?.previousPageUrl?.absoluteString, "https://www.furaffinity.net/msg/submissions/new~44196991@48/")
    }
}
