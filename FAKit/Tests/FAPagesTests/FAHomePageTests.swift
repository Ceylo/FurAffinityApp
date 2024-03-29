//
//  FAHomePageTests.swift
//
//
//  Created by Ceylo on 17/10/2021.
//

import XCTest
@testable import FAPages

final class FAHomePageTests: XCTestCase {
    func testLoggedOutPage_parsedAsExpected() throws {
        let data = testData("www.furaffinity.net:loggedout.html")
        let page = FAHomePage(data: data, baseUri: FAURLs.homeUrl)
        XCTAssertNotNil(page)
        XCTAssertNil(page?.username)
        XCTAssertNil(page?.displayUsername)
        XCTAssertNil(page?.submissionsCount)
        XCTAssertNil(page?.journalsCount)
    }
    
    func testLoggedInPage_parsedAsExpected() throws {
        let data = testData("www.furaffinity.net:loggedin.html")
        let page = FAHomePage(data: data, baseUri: FAURLs.homeUrl)
        XCTAssertNotNil(page)
        XCTAssertEqual(page?.username, "furrycount")
        XCTAssertEqual(page?.displayUsername, "Furrycount")
        XCTAssertEqual(page?.submissionsCount, 2487)
        XCTAssertEqual(page?.journalsCount, 308)
    }
}
