//
//  FASubmissionsPageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FASubmissionsPageTests: XCTestCase {
    func testFirstSubmissionsPage_72SubmissionsParsed() async throws {
        let data = testData("www.furaffinity.net:msg:submissions-firstpage.html")
        let page = await FASubmissionsPage(data: data, baseUri: FAURLs.latest72SubmissionsUrl)
        XCTAssertNotNil(page)
        XCTAssertEqual(page?.submissions.count, 72)
        
        let submission = FASubmissionsPage
            .Submission(sid: 50170538,
                        url: URL(string: "https://www.furaffinity.net/view/50170538/")!,
                        thumbnailUrl: URL(string: "https://t.furaffinity.net/50170538@300-1670718829.jpg")!,
                        thumbnailWidthOnHeightRatio: 1.2658249,
                        title: "Cyberpunk Kitsune",
                        author: "holt-odium",
                        displayAuthor: "Holt-Odium")
        XCTAssertEqual(submission, page?.submissions[0])
    }
    
    func testFirstSubmissionsPage_NextPageUrlParsed() async throws {
        let data = testData("www.furaffinity.net:msg:submissions-firstpage.html")
        let page = await FASubmissionsPage(data: data, baseUri: FAURLs.submissionsUrl)
        XCTAssertNotNil(page)
        XCTAssertNil(page?.previousPageUrl)
        XCTAssertEqual(page?.nextPageUrl?.absoluteString, "https://www.furaffinity.net/msg/submissions/new~49867956@72/")
    }
    
    func testLastSubmissionsPage_PreviousPageUrlParsed() async throws {
        let data = testData("www.furaffinity.net:msg:submissions-lastpage.html")
        let page = await FASubmissionsPage(data: data, baseUri: FAURLs.submissionsUrl)
        XCTAssertNotNil(page)
        XCTAssertNil(page?.nextPageUrl)
        XCTAssertEqual(page?.previousPageUrl?.absoluteString, "https://www.furaffinity.net/msg/submissions/new~36003843@72/")
    }
    
    func testMiddleSubmissionsPage_PreviousAndNextPageUrlsParsed() async throws {
        let data = testData("www.furaffinity.net:msg:submissions-middlepage.html")
        let page = await FASubmissionsPage(data: data, baseUri: FAURLs.submissionsUrl)
        XCTAssertNotNil(page)
        XCTAssertEqual(page?.nextPageUrl?.absoluteString, "https://www.furaffinity.net/msg/submissions/new~49522964@72/")
        XCTAssertEqual(page?.previousPageUrl?.absoluteString, "https://www.furaffinity.net/msg/submissions/new~50170538@72/")
    }
}
