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
        let data = testData("www.furaffinity.net:msg:submissions-firstpage.html")
        let page = try FASubmissionsPage(data: data, url: FAURLs.latest72SubmissionsUrl)
        XCTAssertEqual(page.submissions.count, 72)
        
        let submission = FASubmissionsPage.Submission(
            sid: 60097041,
            url: URL(string: "https://www.furaffinity.net/view/60097041/")!,
            thumbnailUrl: URL(string: "https://t.furaffinity.net/60097041@400-1741112300.jpg")!,
            thumbnailWidthOnHeightRatio: 1.94175,
            title: "On The Wings of Light",
            author: "leilryu",
            displayAuthor: "leilryu"
        )
        XCTAssertEqual(submission, page.submissions[0])
    }
    
    func testFirstSubmissionsPage_NextPageUrlParsed() throws {
        let data = testData("www.furaffinity.net:msg:submissions-firstpage.html")
        let page = try FASubmissionsPage(data: data, url: FAURLs.submissionsUrl)
        XCTAssertNil(page.previousPageUrl)
        XCTAssertEqual(page.nextPageUrl?.absoluteString, "https://www.furaffinity.net/msg/submissions/new~58873864@72/")
    }
    
    func testLastSubmissionsPage_PreviousPageUrlParsed() throws {
        let data = testData("www.furaffinity.net:msg:submissions-lastpage.html")
        let page = try FASubmissionsPage(data: data, url: FAURLs.submissionsUrl)
        XCTAssertNil(page.nextPageUrl)
        XCTAssertEqual(page.previousPageUrl?.absoluteString, "https://www.furaffinity.net/msg/submissions/new~57208617@72/")
    }
    
    func testMiddleSubmissionsPage_PreviousAndNextPageUrlsParsed() throws {
        let data = testData("www.furaffinity.net:msg:submissions-middlepage.html")
        let page = try FASubmissionsPage(data: data, url: FAURLs.submissionsUrl)
        XCTAssertEqual(page.nextPageUrl?.absoluteString, "https://www.furaffinity.net/msg/submissions/new~57208617@72/")
        XCTAssertEqual(page.previousPageUrl?.absoluteString, "https://www.furaffinity.net/msg/submissions/new~60097041@72/")
    }
}
